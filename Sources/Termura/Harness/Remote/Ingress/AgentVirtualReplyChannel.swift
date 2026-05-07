// PR8 §3.6 — virtual reply channel used by the agent-injected ingress
// path. `channelId == cloudSourceDeviceId` so the router's per-channel
// state keys line up with the rest of the CloudKit transport. Reuses
// PR7's `CloudEnvelopeCrypto.seal` + `PairKeyStore` to write encrypted
// `CipherBlob` records back to iCloud; LAN transport never touches
// this channel because the agent only receives CloudKit-routed items.

import CryptoKit
import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "AgentVirtualReplyChannel")

/// D-5 diagnostic — short PairKey fingerprint matching the helper in
/// `CloudKitReplyChannel` and `PairingService+PairKey`. Surfacing
/// it on every cross-network seal lets a Mac encrypt-time fp be
/// cross-referenced against the iOS `iosFp` printed in
/// `CloudKitClientTransport+CipherDecode` when `open` fails. Without
/// this, the agent-injected reply path was a black box and the
/// `iosFp` log line had no Mac counterpart to compare against.
private func pairKeyFingerprint(_ secret: SymmetricKey) -> String {
    let raw = secret.withUnsafeBytes { Data($0) }
    let digest = SHA256.hash(data: raw)
    return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
}

actor AgentVirtualReplyChannel: ReplyChannel {
    enum SendError: Error, Sendable, Equatable, LocalizedError {
        case channelClosed
        case missingPairKey(pairingId: UUID)

        var errorDescription: String? {
            switch self {
            case .channelClosed:
                "Agent virtual reply channel is closed."
            case let .missingPairKey(pairingId):
                "No pair key cached for pairing \(pairingId.uuidString); cannot send envelope."
            }
        }
    }

    nonisolated let channelId: UUID

    private let transportDeviceId: UUID
    private let peerDeviceId: UUID
    private let pairingId: UUID
    private let gateway: any CloudKitDatabaseGateway
    private let pairKeyStore: any PairKeyStore
    private let codec: any RemoteCodec
    private let clock: @Sendable () -> Date
    private var isOpen = true

    init(
        transportDeviceId: UUID,
        peerDeviceId: UUID,
        pairingId: UUID,
        gateway: any CloudKitDatabaseGateway,
        pairKeyStore: any PairKeyStore,
        codec: any RemoteCodec,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        channelId = peerDeviceId
        self.transportDeviceId = transportDeviceId
        self.peerDeviceId = peerDeviceId
        self.pairingId = pairingId
        self.gateway = gateway
        self.pairKeyStore = pairKeyStore
        self.codec = codec
        self.clock = clock
    }

    func send(_ envelope: Envelope) async throws {
        guard isOpen else { throw SendError.channelClosed }
        let pairingId = pairingId
        guard let pairKey = try await pairKeyStore.key(forPairing: pairingId) else {
            throw SendError.missingPairKey(pairingId: pairingId)
        }
        let blob = try CloudEnvelopeCrypto.seal(envelope: envelope, with: pairKey, codec: codec)
        // D-5 diagnostic — encrypt-time fingerprint so a Mac seal can
        // be matched against iOS `iosFp` on `open` failure. Logged
        // before `gateway.save` so a save error doesn't suppress the
        // record we need to localise the mismatch.
        let macFp = pairKeyFingerprint(pairKey.secret)
        logger.info("""
        Sealed envelope kind=\(envelope.kind.rawValue, privacy: .public) \
        pairingId=\(pairingId, privacy: .public) macFp=\(macFp, privacy: .public)
        """)
        let record = CloudKitEnvelopeRecord(
            id: UUID().uuidString,
            payload: .cipher(blob),
            targetDeviceId: peerDeviceId,
            sourceDeviceId: transportDeviceId,
            createdAt: clock()
        )
        try await gateway.save(record)
    }

    func close() async {
        isOpen = false
    }
}
