import CryptoKit
import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "CloudKitReplyChannel")

/// D-5 diagnostic — short fingerprint matching the one in
/// `PairingService+PairKey.swift` so a Mac-side encrypt log line
/// can be cross-referenced with the iOS-side decrypt log line and
/// the pair-time save log line.
private func pairKeyFingerprint(_ secret: SymmetricKey) -> String {
    let raw = secret.withUnsafeBytes { Data($0) }
    let digest = SHA256.hash(data: raw)
    return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
}

/// Virtual reply channel for the CloudKit transport. Each remote device gets
/// exactly one of these on the Mac side; the `channelId` is set to the peer's
/// device id so the router's per-channel auth state survives transient
/// disconnects (CloudKit has no persistent socket).
///
/// PR7 — encryption hook lives here. The channel writes one of two
/// `CloudKitEnvelopeRecord.Payload` shapes:
///   * `.cipher(CipherBlob)` once `setActivePairingId(_:)` has been
///     called and the matching `PairKey` is in the store; the router
///     calls this after `PairingCompleteAck` is sent so business
///     replies always go encrypted.
///   * `.plaintext(envelope)` before then — the bootstrap path used
///     for `pair_init` / `pair_complete` / `error` / `ping` / `pong`
///     during a CloudKit-mode initial pair.
///
/// OWNER: `CloudKitTransport` (lifetime tied to `start`/`stop`)
/// CANCEL: `close()` flips `isOpen` to false; further `send` throws
/// TEARDOWN: `CloudKitTransport.stop()` clears the channel map
actor CloudKitReplyChannel: ReplyChannel {
    nonisolated let channelId: UUID

    private let transportDeviceId: UUID
    private let peerDeviceId: UUID
    private let gateway: any CloudKitDatabaseGateway
    private let pairKeyStore: (any PairKeyStore)?
    private let codec: any RemoteCodec
    private let clock: @Sendable () -> Date
    /// Out-of-band failure sink owned by the parent `CloudKitTransport`.
    /// Called *before* `send` rethrows so the host (Mac Settings UI)
    /// observes the failure even when the router catches the throw and
    /// only logs it.
    private let eventSink: @Sendable (ServerTransportEvent) -> Void
    private var isOpen = true
    private var activePairingId: UUID?

    init(
        transportDeviceId: UUID,
        peerDeviceId: UUID,
        gateway: any CloudKitDatabaseGateway,
        pairKeyStore: (any PairKeyStore)?,
        codec: any RemoteCodec,
        clock: @escaping @Sendable () -> Date,
        eventSink: @escaping @Sendable (ServerTransportEvent) -> Void = { _ in }
    ) {
        channelId = peerDeviceId
        self.transportDeviceId = transportDeviceId
        self.peerDeviceId = peerDeviceId
        self.gateway = gateway
        self.pairKeyStore = pairKeyStore
        self.codec = codec
        self.clock = clock
        self.eventSink = eventSink
    }

    /// Called by the router after `PairingCompleteAck` is queued so
    /// every subsequent `send` seals the envelope with the per-pair
    /// symmetric key.
    func setActivePairingId(_ id: UUID?) {
        activePairingId = id
    }

    func send(_ envelope: Envelope) async throws {
        guard isOpen else { throw TransportError.notRunning }
        let payload: CloudKitEnvelopeRecord.Payload
        if let pairKey = await resolvePairKey() {
            // D-5 diagnostic — log encrypt-time fingerprint so a Mac
            // ↔ iOS mismatch can be confirmed across processes.
            logger.info("""
            Encrypting reply pairingId=\(pairKey.pairingId, privacy: .public) \
            fp=\(pairKeyFingerprint(pairKey.secret), privacy: .public) \
            kind=\(envelope.kind.rawValue, privacy: .public)
            """)
            do {
                let blob = try CloudEnvelopeCrypto.seal(
                    envelope: envelope,
                    with: pairKey,
                    codec: codec
                )
                payload = .cipher(blob)
            } catch {
                let reason = "seal failed: \(error.localizedDescription)"
                emitSendFailure(reason: reason)
                throw TransportError.sendFailure(reason: reason)
            }
        } else {
            // Pair-handshake bootstrap: no key yet, fall through to
            // plaintext for the small envelope-kind set the router
            // emits during this phase.
            payload = .plaintext(envelope)
        }
        let record = CloudKitEnvelopeRecord(
            id: UUID().uuidString,
            payload: payload,
            targetDeviceId: peerDeviceId,
            sourceDeviceId: transportDeviceId,
            createdAt: clock()
        )
        do {
            try await gateway.save(record)
        } catch {
            let reason = error.localizedDescription
            emitSendFailure(reason: reason)
            throw TransportError.sendFailure(reason: reason)
        }
    }

    private func emitSendFailure(reason: String) {
        eventSink(.replyChannelSendFailed(
            peerDeviceId: peerDeviceId,
            reason: reason,
            occurredAt: clock()
        ))
    }

    func close() async {
        isOpen = false
    }

    private func resolvePairKey() async -> PairKey? {
        guard let id = activePairingId, let store = pairKeyStore else { return nil }
        do {
            return try await store.key(forPairing: id)
        } catch {
            logger.warning("PairKey lookup failed for \(id): \(error.localizedDescription)")
            return nil
        }
    }
}
