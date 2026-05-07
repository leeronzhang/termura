// Mac is the source of truth for the session list; the host fires
// `adapter.sessionListChanges()` on every open / close. The router fans out
// a fresh `sessionList` envelope to every authenticated channel so iOS
// never has to poll. This complements the existing `replyWithSessionList`
// pull path, which still serves the iOS refresh-on-foreground hook and the
// very first sync after pair.
//
// Lives in its own file (mirrors `+ChannelPriming.swift`) so the broadcast
// concern doesn't inflate the main router file past its size budget — see
// CLAUDE.md §6.1 / §10. `replyChannels`, `channels`, `broadcastTask`, and
// the shared codec helper are module-internal so this same-module extension
// can reach them without widening the router's public surface.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+Broadcast")

extension RemoteEnvelopeRouter {
    /// Subscribe to the host's session-change ticks and start broadcasting.
    /// Idempotent — a second call replaces the prior task so harness
    /// restarts leave only one observer behind.
    func startBroadcasting() {
        broadcastTask?.cancel()
        let stream = adapter.sessionListChanges()
        broadcastTask = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                await broadcastSessionList()
            }
        }
    }

    /// Tear down the change observer. Called by `RemoteServerHarness.stop()`
    /// before the underlying transports stop so we never queue a broadcast
    /// after the channels are gone.
    func stopBroadcasting() {
        broadcastTask?.cancel()
        broadcastTask = nil
    }

    /// Snapshot the host's session list and push it to every authenticated
    /// channel. Encoding failures on a single channel are logged and skipped
    /// so one wedged transport can't starve the others.
    func broadcastSessionList() async {
        guard !replyChannels.isEmpty else { return }
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
        for (channelId, channel) in replyChannels {
            guard case .authenticated = channels[channelId, default: .unauthenticated] else { continue }
            let codec = codec(for: channelId)
            do {
                let envelope = try Envelope.encode(payload, kind: .sessionList, codec: codec)
                try await channel.send(envelope)
            } catch {
                logger.warning(
                    "Broadcast sessionList failed on \(channelId): \(error.localizedDescription)"
                )
            }
        }
    }
}
