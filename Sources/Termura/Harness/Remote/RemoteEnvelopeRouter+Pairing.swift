// `pair_init` handling lives in its own file so the main router file
// stays under the file_length budget. The actor's `channels`,
// `phases`, `replyChannels`, `pairingService`, `cloudKitChannelActivator`,
// and the codec helpers are module-internal so this same-module
// extension can drive the handshake without going through public
// hops.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+Pairing")

extension RemoteEnvelopeRouter {
    func handlePairInit(envelope: Envelope, replyChannel: any ReplyChannel) async {
        let request: PairingChallengeResponse
        do {
            request = try decodePairInitRequest(envelope: envelope)
        } catch {
            await replyError(.commandRejected, message: "Bad pairing payload", origin: envelope, via: replyChannel)
            return
        }
        do {
            let device = try await pairingService.completePairing(
                token: request.token,
                devicePublicKey: request.devicePublicKey,
                nickname: request.nickname,
                signature: request.signature,
                kemPublicKey: request.kemPublicKey
            )
            await finalizeAuthenticatedChannel(
                device: device,
                request: request,
                envelope: envelope,
                replyChannel: replyChannel
            )
        } catch let error as PairingError {
            await replyError(.unauthorized, message: String(describing: error), origin: envelope, via: replyChannel)
        } catch {
            await replyError(.internalFailure, message: error.localizedDescription, origin: envelope, via: replyChannel)
        }
    }

    /// Handshake-phase decode. Always uses `handshakeCodec` explicitly so a
    /// retry on a partially-flipped channel can't accidentally reach for an
    /// active codec.
    private func decodePairInitRequest(envelope: Envelope) throws -> PairingChallengeResponse {
        try envelope.decode(PairingChallengeResponse.self, codec: handshakeCodec)
    }

    /// Wraps the post-`completePairing` plumbing: register the channel,
    /// negotiate the codec, send the ack while still in handshake (JSON),
    /// flip the phase, activate the CloudKit reply channel for encrypted
    /// mode, and persist the negotiation so a fresh main-app process can
    /// rebuild `phases` without re-handshaking.
    private func finalizeAuthenticatedChannel(
        device: PairedDevice,
        request: PairingChallengeResponse,
        envelope: Envelope,
        replyChannel: any ReplyChannel
    ) async {
        channels[replyChannel.channelId] = .authenticated(deviceId: device.id)
        replyChannels[replyChannel.channelId] = replyChannel
        let agreedCodec = await pairingService.negotiateCodec(remoteSupported: request.supportedCodecs)
        // PR7 — echo the pairingId Mac picked when issuing the
        // invitation so iOS can persist its derived `PairKey` under
        // the same id Mac used. `UUID()` fallback preserves the ack
        // shape for legacy clients that ignore the field. PR8 keeps
        // the real value separate so `persistNegotiation` only writes
        // when there is an actual pair key to address.
        let actualPairingId = await pairingService.lastCompletedPairingId()
        let ackPairingId = actualPairingId ?? UUID()
        let ack = PairingCompleteAck(
            deviceId: device.id,
            pairedAt: device.pairedAt,
            negotiatedCodec: agreedCodec,
            pairingId: ackPairingId
        )
        // Wave 2 — flip the channel's phase BEFORE sending the ack so
        // there is no window in which a fast iOS client can land its
        // first business envelope (encoded with the agreed codec)
        // before the server's `phases[…]` map has flipped. The pre-
        // Wave-2 order set the phase after `replyEncoded`, leaving a
        // tight race where the next inbound `cmd_exec` would be
        // decoded with `handshakeCodec` and rejected as
        // `Bad command payload`. `replyEncoded` keys its codec choice
        // off `Envelope.Kind.isAllowedDuringHandshake` (true for
        // `.pairComplete`), not off `phases[…]`, so the ack still
        // ships as JSON regardless of phase state.
        phases[replyChannel.channelId] = .active(agreedCodec)
        await replyEncoded(ack, kind: .pairComplete, origin: envelope, via: replyChannel)
        await activateCloudKitChannelIfNeeded(device: device, ackPairingId: ackPairingId)
        await persistNegotiation(
            deviceId: device.id,
            codec: agreedCodec,
            pairingId: actualPairingId
        )
        logger.info("Paired device \(device.id) on channel \(replyChannel.channelId), codec=\(agreedCodec.rawValue)")
    }

    /// PR7+PR8 — flip the CloudKit reply channel to encrypted mode.
    /// `forSourceDeviceId` is the `cloudSourceDeviceId` (public-key-
    /// derived id the iPhone uses on every CloudKit envelope it
    /// sends). LAN-only builds get `NullCloudKitChannelActivator`,
    /// so the call here is a no-op without any conditional plumbing
    /// at the call site.
    private func activateCloudKitChannelIfNeeded(device: PairedDevice, ackPairingId: UUID) async {
        let cloudSourceDeviceId = device.cloudSourceDeviceId
            ?? DeviceIdentity.deriveDeviceId(from: device.publicKey)
        await cloudKitChannelActivator.activate(
            pairingId: ackPairingId,
            forSourceDeviceId: cloudSourceDeviceId
        )
    }

    /// Wave 4 — rejoin handshake handler. Lets an already-paired iPhone
    /// resume an authenticated session on a fresh transport channel
    /// without consuming a new invitation. Validates timestamp skew,
    /// looks up the paired device by id, verifies the rejoin signature
    /// against the persisted `publicKey`, then primes the same
    /// `channels` / `phases` / `replyChannels` state `handlePairInit`
    /// would have set. Failure modes — clock skew, signature mismatch,
    /// unknown id, revoked device — all surface as typed
    /// `RemoteError` codes the iOS side can branch on
    /// (`.devicePeerRevoked` triggers a fail-flow back to PairingView).
    func handleRejoin(envelope: Envelope, replyChannel: any ReplyChannel) async {
        let request: RejoinRequest
        do {
            request = try envelope.decode(RejoinRequest.self, codec: handshakeCodec)
        } catch {
            await replyError(.commandRejected, message: "Bad rejoin payload",
                             origin: envelope, via: replyChannel)
            return
        }
        guard rejoinTimestampWithinSkew(request.timestamp) else {
            await replyError(.unauthorized,
                             message: "Rejoin timestamp outside the \(Int(RejoinPolicy.timestampSkewTolerance))s skew window",
                             origin: envelope, via: replyChannel)
            return
        }
        let device: PairedDevice
        do {
            let devices = try await pairingService.listPairedDevices()
            guard let match = devices.first(where: { $0.id == request.pairedDeviceId }) else {
                await replyError(.devicePeerRevoked,
                                 message: "This iPhone is not paired with this Mac. " +
                                     "Pair again from Mac Settings → Remote.",
                                 origin: envelope, via: replyChannel)
                return
            }
            device = match
        } catch {
            await replyError(.internalFailure, message: error.localizedDescription,
                             origin: envelope, via: replyChannel)
            return
        }
        guard device.isActive else {
            await replyError(.devicePeerRevoked,
                             message: "This iPhone has been revoked from this Mac. " +
                                 "Pair again from Mac Settings → Remote.",
                             origin: envelope, via: replyChannel)
            return
        }
        guard verifyRejoinSignature(request: request, publicKey: device.publicKey) else {
            await replyError(.unauthorized, message: "Rejoin signature does not match the paired device",
                             origin: envelope, via: replyChannel)
            return
        }
        await finalizeRejoinedChannel(
            device: device,
            request: request,
            envelope: envelope,
            replyChannel: replyChannel
        )
    }

    private func rejoinTimestampWithinSkew(_ timestamp: Date) -> Bool {
        let now = clock()
        let delta = abs(now.timeIntervalSince(timestamp))
        return delta <= RejoinPolicy.timestampSkewTolerance
    }

    private func verifyRejoinSignature(request: RejoinRequest, publicKey: Data) -> Bool {
        let bytes = RejoinRequest.signedBytes(
            pairedDeviceId: request.pairedDeviceId,
            nonce: request.nonce,
            timestamp: request.timestamp
        )
        do {
            return try DeviceSignature.verify(
                signature: request.signature,
                message: bytes,
                publicKey: publicKey
            )
        } catch {
            return false
        }
    }

    /// Mirrors `finalizeAuthenticatedChannel` for the rejoin path:
    /// register the channel, negotiate codec, send `RejoinAck` while
    /// still in handshake, flip phase, activate the CloudKit reply
    /// channel for encrypted mode. The ack carries the existing
    /// `pairingId` so the iPhone keeps using the same persisted
    /// `PairKey` — rejoin doesn't derive a new symmetric key.
    private func finalizeRejoinedChannel(
        device: PairedDevice,
        request: RejoinRequest,
        envelope: Envelope,
        replyChannel: any ReplyChannel
    ) async {
        channels[replyChannel.channelId] = .authenticated(deviceId: device.id)
        replyChannels[replyChannel.channelId] = replyChannel
        let agreedCodec = await pairingService.negotiateCodec(remoteSupported: request.supportedCodecs)
        let ack = RejoinAck(pairedDeviceId: device.id, negotiatedCodec: agreedCodec)
        // Wave 2 — flip phase BEFORE sending the ack so a fast
        // iPhone can't land its first business envelope before the
        // server's `phases[…]` map flips.
        phases[replyChannel.channelId] = .active(agreedCodec)
        await replyEncoded(ack, kind: .rejoinAck, origin: envelope, via: replyChannel)
        if let pairingId = device.pairingId {
            await activateCloudKitChannelIfNeeded(device: device, ackPairingId: pairingId)
        }
        logger.info("Rejoined device \(device.id) on channel \(replyChannel.channelId), codec=\(agreedCodec.rawValue)")
    }
}
