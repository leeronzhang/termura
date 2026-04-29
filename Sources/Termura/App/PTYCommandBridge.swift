import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "PTYCommandBridge")

/// Bridges remote-issued commands (from the active `RemoteIntegration`
/// implementation) onto the live terminal engine and waits for the
/// matching `OutputChunk` to be produced before returning the captured
/// stdout.
///
/// Correlation strategy (PR2c plan §4):
/// 1. Inject an `OSC 133;X;remoteCmdId=<UUID>` sentinel before the command line
/// 2. The shell echoes the sequence; `GhosttyCallbacks.scanOSC133ShellEvents`
///    parses the X marker and raises `.commandMetadata`
/// 3. `ChunkDetector` attaches the metadata to the next chunk it produces
/// 4. We register a `CommandRouter.onChunkCompleted` handler filtering by
///    `metadata["remoteCmdId"]` and resolve when the matching chunk arrives
/// 5. If the sentinel is dropped (shell strips OSC, fallback shells, etc.) the
///    timeout fires and we return a low-confidence best-effort result tagged
///    with `.sentinelMissing`.
///
/// Lifecycle:
/// - OWNER: each `run(...)` call owns its own chunkHandler token and timeout task
/// - CANCEL: external `Task.cancel` (e.g. from `cmd_cancel`) cancels both the
///   chunkHandler's hosting Task and the wait
/// - TEARDOWN: every exit path (success, timeout, cancellation, throw)
///   removes the chunkHandler via `defer`-style guard
@MainActor
enum PTYCommandBridge {
    /// Default deadline before falling back to best-effort capture. Picked to
    /// cover the 95th percentile of interactive commands without keeping a
    /// remote client blocked indefinitely on misbehaving shells.
    static let defaultTimeout: Duration = .seconds(30)

    /// Public marker key embedded in the OSC 133;X sentinel.
    static let remoteCmdIdKey = "remoteCmdId"

    enum Failure: Error, Equatable {
        case sessionNotFound
        case noActiveProject
        case engineSendFailed
    }

    struct Result {
        let stdout: String
        let exitCode: Int32?
        /// True when we matched the sentinel; false when the timeout fallback
        /// fired and the stdout is best-effort.
        let isSentinelMatched: Bool
    }

    static func run(
        line: String,
        sessionId: SessionID,
        commandId: UUID,
        scope: SessionScope,
        commandRouter: CommandRouter,
        timeout: Duration = defaultTimeout
    ) async throws -> Result {
        guard let engine = scope.engines.engine(for: sessionId) else {
            throw Failure.sessionNotFound
        }

        let stream = subscribe(to: commandRouter, commandId: commandId, sessionId: sessionId)

        // Inject sentinel before the user-visible command. The marker is invisible
        // because OSC sequences don't render in normal terminals; the shell sees
        // it as a trivial `printf` no-op preceding the real command.
        let sentinel = sentinelCommand(commandId: commandId)
        await engine.send(sentinel + " ; " + line)
        await engine.pressReturn()

        do {
            return try await awaitChunkOrTimeout(
                stream: stream,
                timeout: timeout
            )
        } catch is CancellationError {
            logger.info("Remote command \(commandId.uuidString) cancelled while awaiting output")
            throw CancellationError()
        }
    }

    /// Constructs the OSC 133;X sentinel as a shell-safe `printf`. Compatible
    /// with bash/zsh/fish/POSIX sh — every mainstream shell supports `printf`
    /// and the `\e` / `\a` escapes used here.
    private static func sentinelCommand(commandId: UUID) -> String {
        // ESC ] 1 3 3 ; X ; remoteCmdId=<uuid> BEL
        // Use printf so the bytes hit the PTY before the real command runs.
        "printf '\\e]133;X;\(remoteCmdIdKey)=\(commandId.uuidString)\\a'"
    }

    private static func subscribe(
        to router: CommandRouter,
        commandId: UUID,
        sessionId: SessionID
    ) -> AsyncStream<OutputChunk> {
        AsyncStream { continuation in
            let token = router.onChunkCompleted { chunk in
                guard chunk.sessionID == sessionId else { return }
                guard chunk.metadata[remoteCmdIdKey] == commandId.uuidString else { return }
                continuation.yield(chunk)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                Task { @MainActor in
                    router.removeChunkHandler(token: token)
                }
            }
        }
    }

    private static func awaitChunkOrTimeout(
        stream: AsyncStream<OutputChunk>,
        timeout: Duration
    ) async throws -> Result {
        try await withThrowingTaskGroup(of: TaskResult.self) { group in
            group.addTask {
                for await chunk in stream {
                    return .matched(chunk)
                }
                return .streamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return .timedOut
            }
            defer { group.cancelAll() }
            guard let outcome = try await group.next() else {
                return Result(stdout: "", exitCode: nil, isSentinelMatched: false)
            }
            switch outcome {
            case let .matched(chunk):
                return Result(
                    stdout: chunk.outputLines.joined(separator: "\n"),
                    exitCode: chunk.exitCode.map(Int32.init),
                    isSentinelMatched: true
                )
            case .timedOut:
                logger.warning("PTY sentinel timeout — returning fallback result")
                return Result(
                    stdout: "",
                    exitCode: nil,
                    isSentinelMatched: false
                )
            case .streamEnded:
                logger.warning("PTY chunk stream ended without a match")
                return Result(
                    stdout: "",
                    exitCode: nil,
                    isSentinelMatched: false
                )
            }
        }
    }

    private enum TaskResult: Sendable {
        case matched(OutputChunk)
        case timedOut
        case streamEnded
    }
}
