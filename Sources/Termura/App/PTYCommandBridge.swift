import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "PTYCommandBridge")

/// Bridges remote-issued commands (from the active `RemoteIntegration`
/// implementation) onto the live terminal engine and waits for the next
/// completed `OutputChunk` on the same session before returning.
///
/// Capture strategy:
/// 1. Send the user command verbatim through the engine (no marker
///    injection — the OSC 133;X sentinel we used to inject was visible
///    to the user via shell echo on every command, see git history).
/// 2. `ChunkDetector` completes a chunk when the shell emits OSC 133;D
///    (shell-integration "command finished"). The next-completing chunk
///    on this session is treated as the response.
/// 3. If no chunk completes within `timeout` (REPLs like Claude Code,
///    raw shells without integration) we return an empty best-effort
///    result; iOS now relies on Phase-C live `screenFrame` push for the
///    actual visible content in those cases.
///
/// Concurrency: relies on the remote control flow being serialized at
/// `@MainActor` (one in-flight `runRemoteCommand` per session at a time).
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

    enum Failure: Error, Equatable {
        case sessionNotFound
        case noActiveProject
        case engineSendFailed
    }

    struct Result {
        let stdout: String
        let exitCode: Int32?
        /// True when a chunk completed within the timeout window; false on
        /// timeout (REPL or no-shell-integration session). Callers that
        /// surface to a remote peer use this to decide whether to ship the
        /// captured stdout or a "no output captured" notice.
        let chunkMatched: Bool
    }

    static func run(
        line: String,
        sessionId: SessionID,
        commandId _: UUID,
        scope: SessionScope,
        commandRouter: CommandRouter,
        timeout: Duration = defaultTimeout
    ) async throws -> Result {
        guard let engine = scope.engines.engine(for: sessionId) else {
            throw Failure.sessionNotFound
        }

        let stream = subscribe(to: commandRouter, sessionId: sessionId)

        // Send the user command verbatim. We used to inject an OSC 133;X
        // sentinel (`printf '\e]...'`) before the line so ChunkDetector
        // could attribute the resulting chunk back to this `commandId`,
        // but in practice every shell echoes the literal `printf …`
        // prefix to the PTY (bracketed paste exposes pasted bytes to the
        // shell), polluting the Mac terminal with a long marker line on
        // every remote command. iOS now consumes the live `screenFrame`
        // push (Phase C) to render the actual terminal content, which
        // makes per-command attribution unnecessary for the visible UX.
        // The next-completing chunk on the same session within `timeout`
        // is treated as the response — adequate for the serialized
        // single-user remote control flow we ship today.
        await engine.send(line)
        await engine.pressReturn()

        do {
            return try await awaitChunkOrTimeout(
                stream: stream,
                timeout: timeout
            )
        } catch is CancellationError {
            logger.info("Remote command cancelled while awaiting output")
            throw CancellationError()
        }
    }

    private static func subscribe(
        to router: CommandRouter,
        sessionId: SessionID
    ) -> AsyncStream<OutputChunk> {
        AsyncStream { continuation in
            let token = router.onChunkCompleted { chunk in
                guard chunk.sessionID == sessionId else { return }
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
                return Result(stdout: "", exitCode: nil, chunkMatched: false)
            }
            switch outcome {
            case let .matched(chunk):
                return Result(
                    stdout: chunk.outputLines.joined(separator: "\n"),
                    exitCode: chunk.exitCode.map(Int32.init),
                    chunkMatched: true
                )
            case .timedOut:
                logger.warning("PTY chunk timeout — returning empty best-effort result")
                return Result(
                    stdout: "",
                    exitCode: nil,
                    chunkMatched: false
                )
            case .streamEnded:
                logger.warning("PTY chunk stream ended without a match")
                return Result(
                    stdout: "",
                    exitCode: nil,
                    chunkMatched: false
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
