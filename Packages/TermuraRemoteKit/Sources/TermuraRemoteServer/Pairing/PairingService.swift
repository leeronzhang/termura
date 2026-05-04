import Foundation
import OSLog
import Security
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "PairingService")

public enum PairingError: Error, Sendable, Equatable {
    case noPendingInvitation
    case tokenMismatch
    case tokenExpired
    case signatureInvalid
    /// Retained for source compatibility — `PairingService.completePairing`
    /// no longer throws this case. A duplicate-pubkey re-pair is treated as
    /// idempotent: the existing `PairedDevice` is returned unchanged so the
    /// iOS peer can rebuild its local mirror after an app reinstall.
    @available(*, deprecated, message: "PairingService no longer throws this; pair is idempotent on matching publicKey")
    case alreadyPaired(deviceId: UUID)
    /// PR9 — `revokeAll` saw at least one device whose persistence write
    /// failed. Surviving successes have already been written; the caller
    /// can re-`listPairedDevices()` to compute the success set.
    case revokeAllFailed(failed: [UUID])
}

public actor PairingService {
    let identity: DeviceIdentity
    let tokenIssuer: PairingTokenIssuer
    let store: any PairedDeviceStore
    /// PR7 — symmetric pair-key persistence. Mac derives the key from
    /// the iOS challenge response and saves it under the same
    /// `pairingId` the iOS side uses, so a future encryption layer can
    /// look it up without an extra round-trip.
    let pairKeyStore: any PairKeyStore
    /// PR7 — random salt sources for the per-pair `pairingNonce`.
    /// Injectable so tests can pin the value.
    let nonceProvider: @Sendable () -> Data
    let pairingIdProvider: @Sendable () -> UUID
    let serviceName: String
    let clock: @Sendable () -> Date
    let supportedCodecs: [CodecKind]

    var pendingToken: PairingToken?
    var pendingPairingId: UUID?
    var pendingPairingNonce: Data?
    /// Snapshot of the most recently completed pairing's id. The router
    /// reads this between `completePairing` and `PairingCompleteAck` so
    /// the iOS peer can persist the matching `PairKey` under the right
    /// id without an extra round-trip.
    var lastCompletedPairingIdValue: UUID?

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

    public func cancelPairing() {
        clearPendingState()
        lastCompletedPairingIdValue = nil
    }

    public func completePairing(
        token: String,
        devicePublicKey: Data,
        nickname: String,
        signature: Data,
        kemPublicKey: Data = Data()
    ) async throws -> PairedDevice {
        try validatePending(token: token)
        try verifyChallengeSignature(token: token, publicKey: devicePublicKey, signature: signature)
        if let existing = try await activeDevice(matchingPublicKey: devicePublicKey) {
            return try await idempotentRePair(existing: existing, kemPublicKey: kemPublicKey)
        }
        // Wave 3 — atomic ordering: derive + save the pair key BEFORE
        // adding the device record. A stale extra `PairKey` keyed
        // under a `pendingPairingId` that never got a device is
        // harmless (no device references it; `purgeAllPairings`
        // sweeps both stores). An orphan device record without a
        // matching key is fatal: the iOS peer can't decrypt any
        // CloudKit envelope addressed to it. So we let the key save
        // throw first; if the device-store add then fails we roll
        // back the key entry (best effort) so the user can retry.
        try await deriveAndSavePairKeyIfNeeded(kemPublicKey: kemPublicKey)
        let device = makeFreshPairedDevice(nickname: nickname, devicePublicKey: devicePublicKey)
        do {
            try await store.add(device)
        } catch {
            await rollbackPairKeyAfterDeviceAddFailure(reason: error.localizedDescription)
            throw error
        }
        // Wave 3 — surface the legacy-iOS-without-KEM case as a
        // single warning so the operator knows CloudKit encryption
        // won't engage for this pairing without having to grep logs
        // for the absence of "PairKey persisted". The pair flow
        // itself still succeeds in plaintext-bootstrap mode.
        if kemPublicKey.isEmpty {
            logger.warning("""
            Paired device \(device.id, privacy: .public) without KEM material; \
            CloudKit envelope encryption disabled for this pairing
            """)
        }
        let completedPairingId = pendingPairingId
        clearPendingState()
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

    public static func challenge(token: String, devicePublicKey: Data) -> Data {
        Data(token.utf8) + devicePublicKey
    }

    func activeDevice(matchingPublicKey publicKey: Data) async throws -> PairedDevice? {
        let devices = try await store.load()
        return devices.first { $0.isActive && $0.publicKey == publicKey }
    }

    /// Single point of mutation for the in-flight pair handshake state. Used
    /// by every terminal path of `completePairing` plus `cancelPairing` /
    /// `purgeAllPairings`, so a future field added to the pending set only
    /// needs to be reset here once.
    func clearPendingState() {
        pendingToken = nil
        pendingPairingId = nil
        pendingPairingNonce = nil
    }

    /// First half of `completePairing`'s precondition check. Verifies
    /// there is a pending invitation, the token matches it, and the
    /// invitation hasn't expired. Throws the same typed errors the
    /// inline code used to throw so callers see no observable change.
    private func validatePending(token: String) throws {
        guard let pending = pendingToken else {
            throw PairingError.noPendingInvitation
        }
        guard pending.value == token else {
            throw PairingError.tokenMismatch
        }
        guard pending.isValid(asOf: clock()) else {
            clearPendingState()
            throw PairingError.tokenExpired
        }
    }

    /// Second half of `completePairing`'s precondition check. Recomputes
    /// the canonical challenge bytes and verifies the iOS signature
    /// matches the device public key.
    private func verifyChallengeSignature(
        token: String,
        publicKey: Data,
        signature: Data
    ) throws {
        let challenge = Self.challenge(token: token, devicePublicKey: publicKey)
        let valid = try DeviceSignature.verify(
            signature: signature,
            message: challenge,
            publicKey: publicKey
        )
        guard valid else {
            throw PairingError.signatureInvalid
        }
    }

    /// Builds the fresh `PairedDevice` for the no-existing-match branch.
    /// PR8 populates `cloudSourceDeviceId` and `pairingId` here so the
    /// trusted-source gate has an O(1) reverse map and the router can
    /// address the right symmetric key without an extra lookup.
    private func makeFreshPairedDevice(nickname: String, devicePublicKey: Data) -> PairedDevice {
        PairedDevice(
            nickname: nickname,
            publicKey: devicePublicKey,
            pairedAt: clock(),
            pairingId: pendingPairingId,
            cloudSourceDeviceId: DeviceIdentity.deriveDeviceId(from: devicePublicKey)
        )
    }
}
