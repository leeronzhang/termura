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
        let traceLabel = TraceLocal.current.map { $0.spanName } ?? "untraced"
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
        } catch GitServiceError.commandFailed(_, let code, _) where Self.isNotARepoExitCode(code) {
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
        let traceLabel = TraceLocal.current.map { $0.spanName } ?? "untraced"
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
        } catch GitServiceError.commandFailed(_, let code, _) where Self.isNotARepoExitCode(code) {
            throw GitServiceError.notARepo
        }
    }

    func trackedFiles(at directory: String) async throws -> Set<String> {
        let output: String
        do {
            output = try await run(["ls-files"], at: directory)
        } catch GitServiceError.commandFailed(_, let code, _) where Self.isNotARepoExitCode(code) {
            throw GitServiceError.notARepo
        }
        let paths = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return Set(paths)
    }

    /// Returns the full file content for untracked files (no diff available).
    func showFile(at path: String, directory: String) async throws -> String {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Helpers

    /// Reads all data from `handle` without blocking a Swift cooperative thread.
    /// `readDataToEndOfFile()` is a blocking syscall; offloading it to a detached task
    /// with `.utility` priority keeps the calling cooperative thread free.
    private static func readAllData(from handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }

    /// Git exits 128 for "fatal: not a git repository" and related pre-flight failures.
    /// Mapping exit code 128 to `.notARepo` eliminates the redundant `rev-parse` pre-check.
    private static func isNotARepoExitCode(_ code: Int32) -> Bool { code == 128 }

    private func run(_ arguments: [String], at directory: String) async throws -> String {
        let cmdString = arguments.joined(separator: " ")
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.executeProcess(arguments, at: directory, cmdString: cmdString)
            }
            group.addTask {
                // Hard timeout — if git hangs (lock file, network mount), kill after deadline.
                try await Task.sleep(for: AppConfig.Git.commandTimeout)
                throw GitServiceError.commandFailed(
                    command: cmdString,
                    exitCode: -1,
                    stderr: "Timed out after \(Int(AppConfig.Git.commandTimeout.totalSeconds))s"
                )
            }
            // The first task to complete wins; the other is cancelled.
            guard let result = try await group.next() else {
                throw GitServiceError.commandFailed(command: cmdString, exitCode: -1, stderr: "No result")
            }
            group.cancelAll()
            return result
        }
    }

    private func executeProcess(
        _ arguments: [String],
        at directory: String,
        cmdString: String
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        // Drain pipes in detached tasks BEFORE launch to prevent pipe-buffer deadlock.
        // If readDataToEndOfFile() were called inside terminationHandler, a child
        // producing >64 KB of output would fill the pipe buffer, block on write,
        // never exit, and the handler would never fire.
        // readAllData uses DispatchQueue.global (bounded pool) instead of Task.detached
        // so the blocking pipe read does not occupy a Swift cooperative thread for the
        // lifetime of the git process.
        let stdoutHandle = pipe.fileHandleForReading
        let stderrHandle = errPipe.fileHandleForReading
        let stdoutTask = Task.detached { await Self.readAllData(from: stdoutHandle) }
        let stderrTask = Task.detached { await Self.readAllData(from: stderrHandle) }

        // Wait for process termination via continuation; pipes are already draining.
        // `withTaskCancellationHandler` ensures the OS process is terminated when the
        // Swift Task is cancelled (e.g. when the timeout task wins the race in `run(_:at:)`).
        // Without this, cancelling the Task only stops Swift execution; the child git
        // process would continue running and accumulate as a zombie.
        let exitStatus: Int32 = try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { terminated in
                        continuation.resume(returning: terminated.terminationStatus)
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        // Close handles to unblock the pipe-read threads.
                        // task.cancel() is a no-op for blocking I/O; EOF via close() is required.
                        do { try stdoutHandle.close() } catch {
                            logger.debug("Failed to close stdout handle: \(error.localizedDescription)")
                        }
                        do { try stderrHandle.close() } catch {
                            logger.debug("Failed to close stderr handle: \(error.localizedDescription)")
                        }
                        continuation.resume(throwing: GitServiceError.launchFailed(
                            command: cmdString,
                            underlying: error
                        ))
                    }
                }
            },
            onCancel: {
                // Runs on Task cancellation (e.g. timeout wins the task-group race).
                // Guard with isRunning: terminate() on an unlaunched Process throws
                // NSInvalidArgumentException instead of being a no-op.
                if process.isRunning {
                    process.terminate()
                }
            }
        )

        // Pipe reads complete once the child closes its file descriptors (on exit).
        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value

        guard exitStatus == 0 else {
            let stderr = Self.decodeOutput(stderrData)
            let error = GitServiceError.commandFailed(command: cmdString, exitCode: exitStatus, stderr: stderr)
            logger.warning("\(error.localizedDescription)")
            throw error
        }

        return try Self.decodeStdout(stdoutData, command: cmdString)
    }

    /// Decodes process output, preferring UTF-8 and falling back to Latin-1.
    /// Latin-1 always succeeds (every byte is a valid code point), so the fallback
    /// is safe and preserves content instead of silently returning an empty string.
    private static func decodeOutput(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    /// Decodes stdout, logging a warning when the output is not valid UTF-8.
    /// Throws `decodeFailed` only if Latin-1 decode fails (practically impossible).
    private static func decodeStdout(_ data: Data, command: String) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // Non-UTF-8 output (e.g. Latin-1 filenames in diffs): fall back so callers
        // receive actual content rather than a silent empty string.
        logger.warning("git \(command): stdout is not valid UTF-8, falling back to Latin-1")
        guard let latin1 = String(data: data, encoding: .isoLatin1) else {
            throw GitServiceError.decodeFailed(command: command)
        }
        return latin1
    }
}
