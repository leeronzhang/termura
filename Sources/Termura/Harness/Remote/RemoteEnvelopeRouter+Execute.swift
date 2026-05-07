// Command-execution lifecycle (run-tracking, executor invocation,
// snapshot pack + reply). Split out of `RemoteEnvelopeRouter+Command.swift`
// so that file stays under the file_length budget. The actor's
// `inFlight`, `adapter`, `snapshotPublisher`, codec helpers and
// `replyEncoded` / `replyError` are module-internal so this same-module
// extension drives the lifecycle without a public-actor hop.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+Execute")

extension RemoteEnvelopeRouter {
    /// Wraps `execute(...)` in a `Task` so that `handleCmdCancel` can
    /// cancel it via the `inFlight` map. Awaits the task to preserve
    /// the existing "handler blocks until snapshot sent" semantic; the
    /// actor remains re-entrant during the await, so a `cmd_cancel`
    /// for the same channel can interrupt the suspension.
    func runTrackedExecution(
        command: RemoteCommand,
        origin: Envelope,
        via channel: any ReplyChannel
    ) async {
        let commandId = command.commandId
        let channelId = channel.channelId
        let task = Task {
            await self.execute(command: command, origin: origin, via: channel)
        }
        inFlight[commandId] = InFlightEntry(task: task, channelId: channelId)
        await task.value
        inFlight.removeValue(forKey: commandId)
    }

    private func execute(
        command: RemoteCommand,
        origin: Envelope,
        via channel: any ReplyChannel
    ) async {
        let result: CommandRunResult
        do {
            result = try await adapter.executeCommand(line: command.line, sessionId: command.sessionId)
        } catch {
            await replyError(.commandRejected, message: error.localizedDescription,
                             origin: origin, via: channel)
            return
        }
        let ack = RemoteCommandAck(commandId: command.commandId)
        await replyEncoded(ack, kind: .cmdAck, origin: origin, via: channel)
        await sendSnapshot(command: command, result: result, origin: origin, via: channel)
    }

    private func sendSnapshot(
        command: RemoteCommand,
        result: CommandRunResult,
        origin: Envelope,
        via channel: any ReplyChannel
    ) async {
        let stream = AsyncThrowingStream<CommandOutputEvent, any Error> { continuation in
            continuation.yield(.stdout(result.stdout))
            continuation.yield(.finished(exitCode: result.exitCode))
            continuation.finish()
        }
        let packResult: SnapshotPackResult
        do {
            packResult = try await snapshotPublisher.collect(
                commandId: command.commandId,
                sessionId: command.sessionId,
                stream: stream
            )
        } catch {
            // Stream-level failures (the executor itself blew up before we
            // could pack) leave the client without any snapshot envelope, so
            // surface a `.internalFailure` so the iOS UI can show an error
            // banner rather than appear to hang on this command.
            logger.error("Snapshot collection failed: \(error.localizedDescription)")
            await replyError(
                .internalFailure,
                message: "Snapshot collection failed: \(error.localizedDescription)",
                origin: origin,
                via: channel
            )
            return
        }
        // Always send the snapshot — even when the attachment store rejected
        // the write, the truncated preview + nil `attachmentRef` is the
        // explicit downgraded result the client must still see (per PR6
        // failure semantics: attachment failure must not collapse the entire
        // snapshot into silence).
        await replyEncoded(packResult.snapshot, kind: .snapshotChunk, origin: origin, via: channel)
        if case let .attachmentUnavailable(_, reason) = packResult {
            // OSLog warning is the only persistent server-side trace; the
            // audit log records the *command* outcome (already `.dispatched`
            // earlier in `handleCommandExec`), and conflating an attachment
            // I/O failure with a command rejection there would mislead the
            // user looking at the Settings audit list.
            logger.warning("Attachment unavailable for command \(command.commandId): \(reason)")
        }
    }
}
