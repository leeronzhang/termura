import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "CLIProcessRunner")

/// Output captured from a one-shot child process invocation.
struct CLIProcessOutput: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

enum CLIProcessRunnerError: Error, LocalizedError {
    /// Exec failed before the child even started (binary missing, permission denied, etc.).
    /// Distinct from a non-zero exit code, which is reported via `CLIProcessOutput`.
    case launchFailed(executable: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(executable, underlying):
            "Failed to launch \(executable): \(underlying.localizedDescription)"
        }
    }
}

protocol CLIProcessRunnerProtocol: Sendable {
    /// Spawns `executable` with `args` in `cwd`, captures stdout/stderr, returns when the
    /// process exits or `timeout` elapses (whichever first). The child is sent SIGTERM on timeout.
    func run(
        executable: String,
        args: [String],
        cwd: URL,
        env: [String: String],
        timeout: Duration
    ) async throws -> CLIProcessOutput
}

/// Generic actor that spawns external processes for one-shot invocations
/// (CLI agents, helper tools). Mirrors the pipe-drain + hard-timeout pattern
/// used by `GitService+ProcessExecution` but is decoupled from git semantics.
actor CLIProcessRunner: CLIProcessRunnerProtocol {
    func run(
        executable: String,
        args: [String],
        cwd: URL,
        env: [String: String],
        timeout: Duration
    ) async throws -> CLIProcessOutput {
        try await withThrowingTaskGroup(of: CLIProcessOutput.self) { group in
            group.addTask {
                try await self.execute(executable: executable, args: args, cwd: cwd, env: env)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return CLIProcessOutput(exitCode: -1, stdout: "", stderr: "", timedOut: true)
            }
            guard let result = try await group.next() else {
                return CLIProcessOutput(exitCode: -1, stdout: "", stderr: "", timedOut: true)
            }
            group.cancelAll()
            return result
        }
    }

    private func execute(
        executable: String,
        args: [String],
        cwd: URL,
        env: [String: String]
    ) async throws -> CLIProcessOutput {
        // WHY: Headless CLI invocation must run off the UI path with explicit cancellation
        // and pipe drains so large agent output never deadlocks the child.
        // OWNER: This actor owns the Process plus both drain tasks for the duration of the call.
        // TEARDOWN: runToCompletion + awaited drain tasks ensure the child exits before we return.
        // TEST: Cover happy / non-zero exit / launchFailed / large-output cases via mocks.
        let process = makeProcess(executable: executable, args: args, cwd: cwd, env: env)
        let drains = startDrains(for: process)

        let exitStatus: Int32
        do {
            exitStatus = try await runToCompletion(process: process, drains: drains, executable: executable)
        } catch {
            _ = await drains.stdoutTask.value
            _ = await drains.stderrTask.value
            throw error
        }

        let stdoutData = await drains.stdoutTask.value
        let stderrData = await drains.stderrTask.value

        return CLIProcessOutput(
            exitCode: exitStatus,
            stdout: Self.decode(stdoutData),
            stderr: Self.decode(stderrData),
            timedOut: false
        )
    }

    private func makeProcess(
        executable: String,
        args: [String],
        cwd: URL,
        env: [String: String]
    ) -> Process {
        // WHY: Each CLI invocation is isolated; cwd/env must be set to the user's project + resolved PATH.
        // OWNER: execute() owns this Process for one invocation; teardown happens before return.
        // TEARDOWN: runToCompletion ensures the child has terminated by the time we read stdout/stderr.
        // TEST: Cover invocation with a fake binary path (launchFailed) plus normal exec.
        let process = Process()
        // Resolve via /usr/bin/env so PATH lookup happens with the env we provide,
        // avoiding hardcoded absolute paths that vary across machines.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + args
        process.currentDirectoryURL = cwd
        process.environment = env
        return process
    }

    private struct PipeDrains {
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        let stdoutTask: Task<Data, Never>
        let stderrTask: Task<Data, Never>
    }

    private func startDrains(for process: Process) -> PipeDrains {
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        return PipeDrains(
            stdoutHandle: outHandle,
            stderrHandle: errHandle,
            // WHY: Pipe buffers fill on long agent output and would deadlock the child without concurrent drains.
            // OWNER: This actor's execute() awaits both task values after process exit.
            // TEARDOWN: Each detached task exits when its FileHandle reaches EOF (process closed pipe).
            // TEST: Cover commands that emit > one pipe buffer of stdout.
            stdoutTask: Task.detached { Self.readAll(from: outHandle) },
            stderrTask: Task.detached { Self.readAll(from: errHandle) }
        )
    }

    private func runToCompletion(
        process: Process,
        drains: PipeDrains,
        executable: String
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
                        do { try drains.stdoutHandle.close() } catch {
                            logger.debug("Failed to close stdout pipe: \(error.localizedDescription)")
                        }
                        do { try drains.stderrHandle.close() } catch {
                            logger.debug("Failed to close stderr pipe: \(error.localizedDescription)")
                        }
                        continuation.resume(throwing: CLIProcessRunnerError.launchFailed(
                            executable: executable, underlying: error
                        ))
                    }
                }
            },
            onCancel: { if process.isRunning { process.terminate() } }
        )
    }

    private static func readAll(from handle: FileHandle) -> Data {
        handle.readDataToEndOfFile()
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}
