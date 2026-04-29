import Foundation
import Security
import TermuraRemoteProtocol

public enum PairingError: Error, Sendable, Equatable {
    case noPendingInvitation
    case tokenMismatch
    case tokenExpired
    case signatureInvalid
    case alreadyPaired(deviceId: UUID)
}

public actor PairingService {
    private let identity: DeviceIdentity
    private let tokenIssuer: PairingTokenIssuer
    private let store: any PairedDeviceStore
    /// PR7 — symmetric pair-key persistence. Mac derives the key from
    /// the iOS challenge response and saves it under the same
    /// `pairingId` the iOS side uses, so a future encryption layer can
    /// look it up without an extra round-trip.
    private let pairKeyStore: any PairKeyStore
    /// PR7 — random salt sources for the per-pair `pairingNonce`.
    /// Injectable so tests can pin the value.
    private let nonceProvider: @Sendable () -> Data
    private let pairingIdProvider: @Sendable () -> UUID
    private let serviceName: String
    private let clock: @Sendable () -> Date
    private let supportedCodecs: [CodecKind]

    private var pendingToken: PairingToken?
    private var pendingPairingId: UUID?
    private var pendingPairingNonce: Data?
    /// Snapshot of the most recently completed pairing's id. The router
    /// reads this between `completePairing` and `PairingCompleteAck` so
    /// the iOS peer can persist the matching `PairKey` under the right
    /// id without an extra round-trip.
    private var lastCompletedPairingIdValue: UUID?

    public init(
        identity: DeviceIdentity,
        tokenIssuer: PairingTokenIssuer,
        store: any PairedDeviceStore,
        serviceName: String,
        pairKeyStore: any PairKeyStore = InMemoryPairKeyStore(),
        nonceProvider: @escaping @Sendable () -> Data = { PairingService.randomNonce() },
        pairingIdProvider: @escaping @Sendable () -> UUID = { UUID() },
        clock: @escaping @Sendable () -> Date = { Date() },
        supportedCodecs: [CodecKind] = CodecKind.preferredOrder
    ) {
        self.identity = identity
        self.tokenIssuer = tokenIssuer
        self.store = store
        self.pairKeyStore = pairKeyStore
        self.nonceProvider = nonceProvider
        self.pairingIdProvider = pairingIdProvider
        self.serviceName = serviceName
        self.clock = clock
        self.supportedCodecs = supportedCodecs
    }

    public func beginPairing() -> PairingInvitation {
        let token = tokenIssuer.issue()
        pendingToken = token
        let pairingId = pairingIdProvider()
        let pairingNonce = nonceProvider()
        pendingPairingId = pairingId
        pendingPairingNonce = pairingNonce
        return PairingInvitation(
            token: token.value,
            macPublicKey: identity.publicKeyData,
            serviceName: serviceName,
            expiresAt: token.expiresAt,
            supportedCodecs: supportedCodecs,
            kemPublicKey: identity.kemPublicKeyData,
            pairingNonce: pairingNonce,
            pairingId: pairingId
        )
    }

    /// 16-byte random salt — small enough for HKDF, large enough to
    /// rule out collisions across simultaneous invitations.
    public static func randomNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes)
    }

    public func negotiateCodec(remoteSupported: [CodecKind]) -> CodecKind {
        CodecKind.negotiate(local: supportedCodecs, remote: remoteSupported)
    }

    public func cancelPairing() {
        pendingToken = nil
        pendingPairingId = nil
        pendingPairingNonce = nil
        lastCompletedPairingIdValue = nil
    }

    public func completePairing(
        token: String,
        devicePublicKey: Data,
        nickname: String,
        signature: Data,
        kemPublicKey: Data = Data()
    ) async throws -> PairedDevice {
        guard let pending = pendingToken else {
            throw PairingError.noPendingInvitation
        }
        guard pending.value == token else {
            throw PairingError.tokenMismatch
        }
        guard pending.isValid(asOf: clock()) else {
            pendingToken = nil
            pendingPairingId = nil
            pendingPairingNonce = nil
            throw PairingError.tokenExpired
        }
        let challenge = Self.challenge(token: token, devicePublicKey: devicePublicKey)
        let valid = try DeviceSignature.verify(
            signature: signature,
            message: challenge,
            publicKey: devicePublicKey
        )
        guard valid else {
            throw PairingError.signatureInvalid
        }
        if let existing = try await activeDevice(matchingPublicKey: devicePublicKey) {
            throw PairingError.alreadyPaired(deviceId: existing.id)
        }
        // PR8 — populate the two PR8 identity-domain fields at pair time:
        //   * `cloudSourceDeviceId` is the public-key-derived UUID the
        //     iPhone uses on every CloudKit envelope it sends. Writing it
        //     here gives `TrustedSourceGate` an O(1) reverse-map for
        //     trusted-source classification on the agent side; the field
        //     is then immutable for the lifetime of the pairing because
        //     `publicKey` itself is immutable.
        //   * `pairingId` mirrors the id used in the corresponding
        //     `PairKey` entry, so the router can address the right
        //     symmetric key without an extra lookup. `negotiatedCodec`
        //     stays at the conservative `.json` default until
        //     `recordNegotiation` writes back the agreed codec on the
        //     same pairing path.
        let device = PairedDevice(
            nickname: nickname,
            publicKey: devicePublicKey,
            pairedAt: clock(),
            pairingId: pendingPairingId,
            cloudSourceDeviceId: DeviceIdentity.deriveDeviceId(from: devicePublicKey)
        )
        try await store.add(device)
        // PR7 — derive + persist the pair key. Skipped silently when the
        // iOS peer is on a legacy build that didn't send `kemPublicKey`,
        // so existing pair flows keep working until both sides upgrade.
        let completedPairingId = pendingPairingId
        if !kemPublicKey.isEmpty,
           let pairingId = pendingPairingId,
           let nonce = pendingPairingNonce {
            let pairKey = try PairKeyDerivation.derive(
                localIdentity: identity,
                peerKEMPublic: kemPublicKey,
                pairingNonce: nonce,
                pairingId: pairingId
            )
            try await pairKeyStore.save(pairKey)
        }
        pendingToken = nil
        pendingPairingId = nil
        pendingPairingNonce = nil
        lastCompletedPairingIdValue = completedPairingId
        return device
    }

    /// The pairingId that was active for the most recently completed
    /// pair handshake. Populated even when the iOS peer didn't send a
    /// KEM public key (legacy build) so the ack still echoes a stable
    /// id. Reset on `cancelPairing()`.
    public func lastCompletedPairingId() -> UUID? {
        lastCompletedPairingIdValue
    }

    /// Test / harness diagnostic surface — reads the persisted PairKey
    /// so callers can verify both sides arrived at the same secret. Not
    /// invoked from any production transport in PR7.
    public func storedPairKey(forPairing id: UUID) async throws -> PairKey? {
        try await pairKeyStore.key(forPairing: id)
    }

    /// PR8 — persists the codec the two peers agreed on during the pair
    /// handshake plus the `pairingId` that addresses the symmetric
    /// `PairKey`. Called by the router immediately after `pairComplete`
    /// is queued; both fields are then available to a fresh main-app
    /// process (e.g. one woken by the agent over XPC) without re-running
    /// the handshake.
    ///
    /// `pairedDeviceId` is the paired-device store's primary key —
    /// the UUID owned by the `PairedDevice.id` domain, **not** the
    /// public-key-derived `cloudSourceDeviceId`. The two domains are
    /// kept distinct so the router's `channels[channelId]` map (keyed
    /// on `cloudSourceDeviceId`) can never accidentally collide with
    /// the store's `update(_:)` API (keyed on `id`). See PR8 §3.4.
    public func recordNegotiation(
        pairedDeviceId: UUID,
        negotiatedCodec: CodecKind,
        pairingId: UUID
    ) async throws {
        var devices = try await store.load()
        guard let index = devices.firstIndex(where: { $0.id == pairedDeviceId }) else {
            throw PairedDeviceStoreError.notFound(id: pairedDeviceId)
        }
        devices[index].negotiatedCodec = negotiatedCodec
        devices[index].pairingId = pairingId
        try await store.update(devices[index])
    }

    public func revoke(deviceId: UUID) async throws {
        var devices = try await store.load()
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else {
            throw PairedDeviceStoreError.notFound(id: deviceId)
        }
        devices[index].revokedAt = clock()
        try await store.update(devices[index])
    }

    public func listPairedDevices() async throws -> [PairedDevice] {
        try await store.load()
    }

    public func isPaired(publicKey: Data) async throws -> Bool {
        try await activeDevice(matchingPublicKey: publicKey) != nil
    }

    public static func challenge(token: String, devicePublicKey: Data) -> Data {
        Data(token.utf8) + devicePublicKey
    }

    private func activeDevice(matchingPublicKey publicKey: Data) async throws -> PairedDevice? {
        let devices = try await store.load()
        return devices.first { $0.isActive && $0.publicKey == publicKey }
    }
}
