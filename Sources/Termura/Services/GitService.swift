import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "GitService")

// MARK: - Protocol

protocol GitServiceProtocol: Sendable {
    func status(at directory: String) async throws -> GitStatusResult
    func diff(file: String, staged: Bool, at directory: String) async throws -> String
    /// Returns the set of file paths tracked by git (relative to the repo root).
    func trackedFiles(at directory: String) async throws -> Set<String>
    /// Returns the full file content at `path` relative to `directory` (used for untracked files).
    func showFile(at path: String, directory: String) async throws -> String
    /// Returns per-file added/removed line counts for the working tree (staged + unstaged combined).
    /// Untracked files are not included by `git diff`; callers that need them must combine with `status`.
    func numstat(at directory: String) async throws -> [DiffStat]
}

// MARK: - Live Implementation

/// Actor that shells out to the `git` CLI to query repository state.
/// Uses `OSSignposter` intervals so Instruments can show git operation timing correlated
/// to the calling session. Callers can wrap calls in `withTrace(...)` (from TraceContext.swift)
/// to inject a span label that propagates through `TraceLocal.current`.
actor GitService: GitServiceProtocol {
    private let signposter = OSSignposter(subsystem: "com.termura.app", category: "GitService")

    func status(at directory: String) async throws -> GitStatusResult {
        let traceLabel = TraceLocal.current.map(\.spanName) ?? "untraced"
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("GitStatus", id: signpostID)
        defer { signposter.endInterval("GitStatus", state) }
        logger.debug("GitService.status dir=\(directory) trace=\(traceLabel)")

        // Launch all three git commands concurrently — no data dependencies between them.
        // If status exits 128 (not a repo), the other two async let tasks are implicitly
        // cancelled on early return; withTaskCancellationHandler terminates child processes.
        async let statusFuture = run(
            ["status", "--porcelain=v1", "-b", "--no-renames"],
            at: directory
        )
        async let logFuture = run(
            ["log", "-1", "--oneline", "--no-decorate"],
            at: directory
        )
        async let remoteFuture = run(
            ["remote", "get-url", "origin"],
            at: directory
        )

        let output: String
        do {
            output = try await statusFuture
        } catch let GitServiceError.commandFailed(_, code, _) where Self.isNotARepoExitCode(code) {
            return .notARepo
        }
        var result = Self.parse(porcelain: output)

        // Collect last commit message (non-fatal if fails, e.g. empty repo)
        do {
            let logLine = try await logFuture
            let trimmed = logLine.trimmingCharacters(in: .whitespacesAndNewlines)
            result.lastCommit = trimmed.isEmpty ? nil : trimmed
        } catch {
            logger.debug("Could not read last commit: \(error.localizedDescription)")
        }

        // Collect remote host label (non-fatal if no remote configured)
        do {
            let url = try await remoteFuture
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            result.remoteURL = trimmed.isEmpty ? nil : trimmed
            result.remoteHost = Self.parseRemoteHost(from: trimmed)
        } catch {
            logger.debug("No remote origin: \(error.localizedDescription)")
        }

        return result
    }

    func diff(file: String, staged: Bool, at directory: String) async throws -> String {
        let traceLabel = TraceLocal.current.map(\.spanName) ?? "untraced"
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("GitDiff", id: signpostID)
        defer { signposter.endInterval("GitDiff", state) }
        logger.debug("GitService.diff file=\(file) staged=\(staged) trace=\(traceLabel)")

        var args = ["diff", "--no-color"]
        if staged { args.append("--cached") }
        args.append("--")
        args.append(file)
        do {
            return try await run(args, at: directory)
        } catch let GitServiceError.commandFailed(_, code, _) where Self.isNotARepoExitCode(code) {
            throw GitServiceError.notARepo
        }
    }

    func trackedFiles(at directory: String) async throws -> Set<String> {
        let output: String
        do {
            output = try await run(["ls-files"], at: directory)
        } catch let GitServiceError.commandFailed(_, code, _) where Self.isNotARepoExitCode(code) {
            throw GitServiceError.notARepo
        }
        return Set(output.split(separator: "\n").map(String.init))
    }

    /// Per-file numeric diff stats (added / removed line counts) for the union of
    /// staged + unstaged changes against HEAD. Untracked files are not reported by
    /// `git diff`; callers that want full coverage must merge with `status().untrackedFiles`.
    func numstat(at directory: String) async throws -> [DiffStat] {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("GitNumstat", id: signpostID)
        defer { signposter.endInterval("GitNumstat", state) }

        let output: String
        do {
            output = try await run(["diff", "--numstat", "HEAD"], at: directory)
        } catch let GitServiceError.commandFailed(_, code, _) where Self.isNotARepoExitCode(code) {
            throw GitServiceError.notARepo
        } catch let GitServiceError.commandFailed(_, _, stderr)
            where stderr.contains("unknown revision") || stderr.contains("ambiguous argument 'HEAD'") {
            // Empty repo with no HEAD yet — fall back to staged-only stats.
            return try await numstatStagedOnly(at: directory)
        }
        return Self.parseNumstat(output)
    }

    private func numstatStagedOnly(at directory: String) async throws -> [DiffStat] {
        let output = try await run(["diff", "--numstat", "--cached"], at: directory)
        return Self.parseNumstat(output)
    }

    /// Parses `git diff --numstat` lines:
    ///   "12\t3\tpath/to/file.swift"
    ///   "-\t-\tpath/to/binary.png"        (binary files use `-` for both)
    /// Renamed files appear as e.g. "5\t2\told => new" — we keep `old => new` as the path
    /// since it's user-readable and the popover will display it as-is.
    static func parseNumstat(_ output: String) -> [DiffStat] {
        output.split(separator: "\n").compactMap { rawLine -> DiffStat? in
            let parts = rawLine.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let addedField = String(parts[0])
            let removedField = String(parts[1])
            let path = String(parts[2])
            let added = addedField == "-" ? nil : Int(addedField)
            let removed = removedField == "-" ? nil : Int(removedField)
            return DiffStat(path: path, added: added, removed: removed)
        }
    }

    /// Returns the full file content for untracked files (no diff available).
    /// Validates that the resolved path stays within `directory` (defends against
    /// path traversal via `../` sequences and symlink attacks in malicious repos).
    func showFile(at path: String, directory: String) async throws -> String {
        let rootURL = URL(fileURLWithPath: directory).resolvingSymlinksInPath()
        let fileURL = URL(fileURLWithPath: directory)
            .appendingPathComponent(path)
            .resolvingSymlinksInPath()
        guard fileURL.path.hasPrefix(rootURL.path + "/") || fileURL.path == rootURL.path else {
            logger.warning("Path traversal blocked in showFile: \(path, privacy: .public)")
            throw GitServiceError.pathTraversal(path: path)
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
