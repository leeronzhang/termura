// Connection teardown + envelope-reply helpers split out of
// `RemoteEnvelopeRouter.swift` so that file stays under the
// file_length budget. The actor's `channels`, `phases`,
// `replyChannels`, `pending`, `inFlight`, `screenSubscriptions`,
// `ptyStreamSubscriptions`, `agentEventSubscriptions`,
// `handshakeCodec`, and `codec(for:)` are module-internal so this
// same-module extension drives the close + reply paths without
// going through a public-actor hop.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+Reply")

extension RemoteEnvelopeRouter {
    func connectionClosed(channelId: UUID) async {
        cancelAllScreenSubscriptions(channelId: channelId)
        await cancelAllPtyStreamSubscriptions(channelId: channelId)
        await cancelAllAgentEventSubscriptions(channelId: channelId)
        channels.removeValue(forKey: channelId)
        phases.removeValue(forKey: channelId)
        replyChannels.removeValue(forKey: channelId)
        pending = pending.filter { _, value in value.channelId != channelId }
        // Cancel any in-flight task tied to this channel; the snapshot reply
        // would have nowhere to go anyway.
        for (commandId, entry) in inFlight where entry.channelId == channelId {
            entry.task.cancel()
            inFlight.removeValue(forKey: commandId)
        }
        logger.info("Remote connection \(channelId) closed")
    }

    func replyEncoded(
        _ value: some Encodable,
        kind: Envelope.Kind,
        origin: Envelope,
        via channel: any ReplyChannel
    ) async {
        do {
            // `pairComplete` is the last envelope of the handshake phase and
            // must therefore stay JSON; pick the codec by inspecting the kind
            // rather than the channel's already-flipped phase.
            let codec = kind.isAllowedDuringHandshake ? handshakeCodec : codec(for: channel.channelId)
            let data = try codec.encode(value)
            await reply(kind: kind, payload: data, origin: origin, via: channel)
        } catch {
            logger.error("Encode \(kind.rawValue) failed: \(error.localizedDescription)")
        }
    }

    func reply(
        kind: Envelope.Kind,
        payload: Data,
        origin: Envelope,
        via channel: any ReplyChannel
    ) async {
        let response = Envelope(version: origin.version, kind: kind, payload: payload)
        do {
            try await channel.send(response)
        } catch {
            logger.error("Send \(kind.rawValue) failed: \(error.localizedDescription)")
        }
    }

    func replyError(
        _ code: RemoteError.Code,
        message: String,
        origin: Envelope,
        via channel: any ReplyChannel
    ) async {
        let err = RemoteError(code: code, message: message, relatedId: origin.id)
        await replyEncoded(err, kind: .error, origin: origin, via: channel)
    }
}
