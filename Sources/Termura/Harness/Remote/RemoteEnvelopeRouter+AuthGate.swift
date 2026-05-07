// Wave 4 — `requireActiveDevice` + `isRevokedDevice` helpers used by
// `RemoteEnvelopeRouter.dispatch` to gate every business envelope on
// `.authenticated` channel state plus a non-revoked paired device.
// Lives in its own file so the main router stays under the
// file_length budget. The actor's stored properties (`channels`,
// `phases`, `replyChannels`, `pairingService`) are module-internal
// so this same-module extension can drive the gate without going
// through public hops.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+AuthGate")

extension RemoteEnvelopeRouter {
    /// Returns true when the caller should proceed; on false it has
    /// already sent the appropriate `.error` envelope. The revoke
    /// check consults the paired-device store as the authoritative
    /// source so a revoke that landed after this channel was primed
    /// still kicks in on the next envelope — the channel itself
    /// doesn't carry a `revokedAt` field.
    func requireActiveDevice(
        envelope: Envelope,
        replyChannel: any ReplyChannel,
        unauthorizedMessage: String
    ) async -> Bool {
        let state = channels[replyChannel.channelId, default: .unauthenticated]
        guard case let .authenticated(deviceId) = state else {
            await replyError(.unauthorized, message: unauthorizedMessage,
                             origin: envelope, via: replyChannel)
            return false
        }
        guard await isRevokedDevice(id: deviceId) else { return true }
        // The iPhone discovers a Mac-side revoke on the next business
        // envelope. Tear down the channel state so a subsequent
        // envelope on the same socket goes through the full handshake
        // again instead of looping on the same revoke reply.
        channels.removeValue(forKey: replyChannel.channelId)
        phases.removeValue(forKey: replyChannel.channelId)
        replyChannels.removeValue(forKey: replyChannel.channelId)
        await replyError(
            .devicePeerRevoked,
            message: "This iPhone has been revoked from this Mac. " +
                "Pair again from Mac Settings → Remote.",
            origin: envelope, via: replyChannel
        )
        return false
    }

    func isRevokedDevice(id: UUID) async -> Bool {
        do {
            let devices = try await pairingService.listPairedDevices()
            guard let match = devices.first(where: { $0.id == id }) else {
                // Device id not in store — treat as revoked. Happens
                // after `purgeAllPairings` while a stale channel
                // still holds an `.authenticated` entry.
                return true
            }
            return !match.isActive
        } catch {
            // Best-effort: a paired-device-store load failure leaves
            // the channel as it was. The next envelope re-evaluates;
            // logging here keeps the failure grep-able without
            // breaking the live session.
            logger.warning("paired-device load failed during revoke check: \(error.localizedDescription)")
            return false
        }
    }
}
