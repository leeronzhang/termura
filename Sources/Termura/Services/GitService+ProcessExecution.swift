import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "GitService")

extension GitService {
    /// Reads all data from `handle` without blocking a Swift cooperative thread.
    /// `readDataToEndOfFile()` is a blocking syscall; offloading it to a detached task
    /// with `.utility` priority keeps the calling cooperative thread free.
    static func readAllData(from handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            // WHY: FileHandle.readDataToEndOfFile() blocks a thread and must stay off the cooperative executor.
            // OWNER: The caller owns this detached drain task and awaits the continuation result inline.
            // TEARDOWN: The detached task exits after one blocking read and releases the continuation immediately.
            // TEST: Cover large stdout/stderr drains so git output cannot deadlock the child process.
            Task.detached(priority: .utility) {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }

    /// Git exits 128 for "fatal: not a git repository" and related pre-flight failures.
    /// Mapping exit code 128 to `.notARepo` eliminates the redundant `rev-parse` pre-check.
    static func isNotARepoExitCode(_ code: Int32) -> Bool { code == 128 }

    func run(_ arguments: [String], at directory: String) async throws -> String {
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
        // WHY: Git subprocess execution must happen off the UI path with explicit cancellation and drain ownership.
        // OWNER: GitService owns the Process instance plus both drain tasks for the duration of this command.
        // TEARDOWN: runToCompletion + awaited drain tasks ensure the child exits and both pipes finish before return.
        // TEST: Cover success, timeout, cancellation, and large-output commands.
        let process = makeGitProcess(arguments: arguments, at: directory)
        let drains = startPipeDrains(for: process)

        let exitStatus = try await runToCompletion(
            process, stdoutHandle: drains.stdoutHandle, stderrHandle: drains.stderrHandle, cmdString: cmdString
        )

        let stdoutData = await drains.stdoutTask.value
        let stderrData = await drains.stderrTask.value

        guard exitStatus == 0 else {
            let stderr = Self.decodeOutput(stderrData)
            let error = GitServiceError.commandFailed(command: cmdString, exitCode: exitStatus, stderr: stderr)
            logger.warning("\(error.localizedDescription)")
            throw error
        }
        return try Self.decodeStdout(stdoutData, command: cmdString)
    }

    private func makeGitProcess(arguments: [String], at directory: String) -> Process {
        // WHY: Each git invocation needs an isolated Process configured with the target cwd/env.
        // OWNER: executeProcess owns this Process instance until runToCompletion finishes.
        // TEARDOWN: runToCompletion terminates or cancels the subprocess before executeProcess returns.
        // TEST: Cover successful launch, timeout cancellation, and not-a-repo failures.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = ProcessInfo.processInfo.environment
        return process
    }

    /// Pipe handles and background drain tasks attached to a process before launch.
    private struct PipeDrains {
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        let stdoutTask: Task<Data, Never>
        let stderrTask: Task<Data, Never>
    }

    /// Attaches pipes to `process` and starts background drains. Must be called before `process.run()`.
    private func startPipeDrains(for process: Process) -> PipeDrains {
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        let stdoutHandle = pipe.fileHandleForReading
        let stderrHandle = errPipe.fileHandleForReading
        return PipeDrains(
            stdoutHandle: stdoutHandle,
            stderrHandle: stderrHandle,
            // WHY: Child process pipes must be drained concurrently to avoid pipe-buffer deadlock.
            // OWNER: executeProcess owns these detached drain tasks through the returned PipeDrains value.
            // TEARDOWN: executeProcess awaits both task values after process exit before returning or throwing.
            // TEST: Cover commands that emit enough stdout/stderr to fill pipe buffers.
            stdoutTask: Task.detached { await Self.readAllData(from: stdoutHandle) },
            stderrTask: Task.detached { await Self.readAllData(from: stderrHandle) }
        )
    }

    /// Launches `process` and waits for it to exit, cancelling via SIGTERM if the Task is cancelled.
    private func runToCompletion(
        _ process: Process,
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle,
        cmdString: String
    ) async throws -> Int32 {
        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { terminated in
                        continuation.resume(returning: terminated.terminationStatus)
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
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
            onCancel: { if process.isRunning { process.terminate() } }
        )
    }

    /// Decodes process output, preferring UTF-8 and falling back to Latin-1.
    static func decodeOutput(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    /// Decodes stdout, logging a warning when the output is not valid UTF-8.
    static func decodeStdout(_ data: Data, command: String) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        logger.warning("git \(command): stdout is not valid UTF-8, falling back to Latin-1")
        guard let latin1 = String(data: data, encoding: .isoLatin1) else {
            throw GitServiceError.decodeFailed(command: command)
        }
        return latin1
    }
}
