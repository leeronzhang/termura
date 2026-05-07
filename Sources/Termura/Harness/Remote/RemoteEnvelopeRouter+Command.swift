// Command-execution kernel: cmd_exec / cmd_cancel / cmd_confirm_response
// plus the shared snapshot-pack reply path. Lives in its own file so
// the main router file stays under the file_length budget; the
// actor's `policy`, `pending`, `inFlight`, `adapter`, `snapshotPublisher`,
// codec helpers, and audit log are module-internal so this same-module
// extension can drive the lifecycle without a public-actor hop.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+Command")

extension RemoteEnvelopeRouter {
    func handleCommandExec(envelope: Envelope, replyChannel: any ReplyChannel) async {
        let command: RemoteCommand
        do {
            command = try envelope.decode(RemoteCommand.self, codec: codec(for: replyChannel.channelId))
        } catch {
            await replyError(.commandRejected, message: "Bad command payload",
                             origin: envelope, via: replyChannel)
            return
        }
        // Single-confirmation strategy (architecture plan §PR5 option A):
        // - Client must run `DangerousCommandPolicy.evaluate(line)` itself,
        //   show its own UI, and gate dangerous commands behind biometric
        //   authentication BEFORE sending the envelope.
        // - The server re-evaluates as zero-trust insurance. If client and
        //   server disagree, OR a dangerous command arrives without
        //   `biometricVerified == true`, we reject and log a security warning
        //   rather than silently re-prompting (which would let a malicious
        //   client double-spend the user's confirmation tap).
        let auditDeviceId = deviceId(for: replyChannel.channelId)
        guard await passesPolicyGate(
            command: command,
            envelope: envelope,
            replyChannel: replyChannel,
            auditDeviceId: auditDeviceId
        ) else { return }
        await recordAudit(
            deviceId: auditDeviceId,
            command: command,
            verdict: policy.evaluate(command.line).verdict,
            outcome: .dispatched
        )
        await runTrackedExecution(command: command, origin: envelope, via: replyChannel)
    }

    /// Re-runs server-side `DangerousCommandPolicy`, audits + replies
    /// with `error` on the three reject paths (blocked / mismatch /
    /// missing biometric), and returns whether dispatch should
    /// continue. Pulled out of `handleCommandExec` to keep that body
    /// inside the function-length budget.
    private func passesPolicyGate(
        command: RemoteCommand,
        envelope: Envelope,
        replyChannel: any ReplyChannel,
        auditDeviceId: UUID?
    ) async -> Bool {
        let serverEvaluation = policy.evaluate(command.line)
        if serverEvaluation.verdict == .blocked {
            let reason = serverEvaluation.matchedReason ?? "blocked by policy"
            await recordAudit(
                deviceId: auditDeviceId,
                command: command,
                verdict: serverEvaluation.verdict,
                outcome: .rejected(reason: reason)
            )
            await replyError(.commandRejected, message: "Blocked: \(reason)",
                             origin: envelope, via: replyChannel)
            return false
        }
        if serverEvaluation.verdict != command.clientPreCheck {
            let mismatchMessage = "Client preCheck mismatch for \(command.commandId): " +
                "client=\(command.clientPreCheck.rawValue) " +
                "server=\(serverEvaluation.verdict.rawValue) line=\(command.line)"
            logger.warning("\(mismatchMessage, privacy: .public)")
            await recordAudit(
                deviceId: auditDeviceId,
                command: command,
                verdict: serverEvaluation.verdict,
                outcome: .rejected(reason: "policy mismatch")
            )
            await replyError(
                .policyMismatch,
                message: "Server policy disagrees with client (server=\(serverEvaluation.verdict.rawValue))",
                origin: envelope,
                via: replyChannel
            )
            return false
        }
        if serverEvaluation.verdict == .requiresConfirmation, !command.biometricVerified {
            logger.warning("Dangerous command \(command.commandId) arrived without biometric verification")
            await recordAudit(
                deviceId: auditDeviceId,
                command: command,
                verdict: serverEvaluation.verdict,
                outcome: .rejected(reason: "missing biometric verification")
            )
            await replyError(
                .commandRejected,
                message: "Dangerous command requires biometric verification",
                origin: envelope,
                via: replyChannel
            )
            return false
        }
        return true
    }

    func handleCmdCancel(envelope: Envelope, replyChannel: any ReplyChannel) async {
        let cancel: RemoteCommandCancel
        do {
            cancel = try envelope.decode(RemoteCommandCancel.self, codec: codec(for: replyChannel.channelId))
        } catch {
            await replyError(.commandRejected, message: "Bad cancel payload",
                             origin: envelope, via: replyChannel)
            return
        }
        // Pending (awaiting confirmation) — drop without invoking adapter.
        if let entry = pending[cancel.commandId], entry.channelId == replyChannel.channelId {
            pending.removeValue(forKey: cancel.commandId)
            let ack = RemoteCommandAck(commandId: cancel.commandId)
            await replyEncoded(ack, kind: .cmdAck, origin: envelope, via: replyChannel)
            logger.info("Cancelled pending command \(cancel.commandId)")
            return
        }
        // In-flight — cancel the running task. The execute task observes
        // `Task.isCancelled` to short-circuit cooperatively (full cancellation
        // semantics land with the PTY bridge in PR2c).
        if let entry = inFlight[cancel.commandId], entry.channelId == replyChannel.channelId {
            entry.task.cancel()
            inFlight.removeValue(forKey: cancel.commandId)
            let ack = RemoteCommandAck(commandId: cancel.commandId)
            await replyEncoded(ack, kind: .cmdAck, origin: envelope, via: replyChannel)
            logger.info("Cancelled in-flight command \(cancel.commandId)")
            return
        }
        await replyError(.commandRejected, message: "No in-flight or pending command \(cancel.commandId)",
                         origin: envelope, via: replyChannel)
    }

    func handleConfirmResponse(envelope: Envelope, replyChannel: any ReplyChannel) async {
        let response: RemoteConfirmResponse
        do {
            response = try envelope.decode(RemoteConfirmResponse.self, codec: codec(for: replyChannel.channelId))
        } catch {
            await replyError(.commandRejected, message: "Bad confirm payload",
                             origin: envelope, via: replyChannel)
            return
        }
        guard let entry = pending.removeValue(forKey: response.commandId) else {
            await replyError(.commandRejected, message: "No pending command \(response.commandId)",
                             origin: envelope, via: replyChannel)
            return
        }
        guard entry.channelId == replyChannel.channelId else {
            await replyError(.unauthorized, message: "Confirmation must come from issuing channel",
                             origin: envelope, via: replyChannel)
            return
        }
        guard response.approved else {
            await replyError(.commandRejected, message: "Rejected by user",
                             origin: envelope, via: replyChannel)
            logger.info("User rejected dangerous command \(response.commandId)")
            return
        }
        await runTrackedExecution(command: entry.command, origin: envelope, via: replyChannel)
    }

    func replyWithSessionList(origin: Envelope, via channel: any ReplyChannel) async {
        let infos = await adapter.listSessions()
        let descriptors = infos.map { info in
            SessionDescriptor(
                id: info.id,
                title: info.title,
                workingDirectory: info.workingDirectory,
                lastActivityAt: info.lastActivityAt
            )
        }
        let payload = SessionListPayload(sessions: descriptors)
        await replyEncoded(payload, kind: .sessionList, origin: origin, via: channel)
    }
}
