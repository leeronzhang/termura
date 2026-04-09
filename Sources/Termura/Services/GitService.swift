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
            result.remoteHost = Self.parseRemoteHost(from: url.trimmingCharacters(in: .whitespacesAndNewlines))
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
