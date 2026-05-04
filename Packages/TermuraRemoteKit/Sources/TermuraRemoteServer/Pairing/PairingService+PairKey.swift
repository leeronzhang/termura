// Pair-key derivation + idempotent re-pair helpers split out of
// `PairingService.swift` so that file stays under the file_length
// budget. The actor's stored properties (`identity`, `pairKeyStore`,
// `pendingPairingId`, `pendingPairingNonce`,
// `lastCompletedPairingIdValue`, `store`, `clearPendingState()`) are
// module-internal so this same-module extension drives the pair-key
// + re-pair plumbing without going through public hops.

import CryptoKit
import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "PairingService+PairKey")

/// D-5 diagnostic — short fingerprint of a PairKey secret so the
/// Mac side and iOS side can be cross-referenced in the log
/// without exposing the raw symmetric key. Prefix only (8 hex
/// chars = 32 bits); enough entropy to spot a mismatch, not
/// enough to brute-force the secret.
private func pairKeyFingerprint(_ secret: SymmetricKey) -> String {
    let raw = secret.withUnsafeBytes { Data($0) }
    let digest = SHA256.hash(data: raw)
    return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
}

extension PairingService {
    /// Wave 6 — re-derives the symmetric `PairKey` using the **current**
    /// invitation's `pendingPairingNonce` and saves it under
    /// `existing.pairingId`. iOS always derives eagerly from each fresh
    /// invitation and overwrites its keychain entry under
    /// `ack.pairingId` (= `existing.pairingId` on this branch); without
    /// the matching refresh on Mac, the two ends end up with different
    /// secrets keyed under the same id, so every encrypted business
    /// envelope after re-pair fails decryption (observed in the field
    /// as `CloudEnvelopeCrypto.open failed` ~minutes after a successful
    /// "Paired device" log line).
    func idempotentRePair(
        existing: PairedDevice,
        kemPublicKey: Data
    ) async throws -> PairedDevice {
        if let pairingId = existing.pairingId {
            try await refreshPairKeyForRePair(
                kemPublicKey: kemPublicKey,
                existingPairingId: pairingId
            )
        }
        clearPendingState()
        lastCompletedPairingIdValue = existing.pairingId
        if existing.cloudSourceDeviceId == nil {
            do {
                try await store.backfillCloudSourceDeviceIdIfMissing(
                    deriving: DeviceIdentity.deriveDeviceId(from:)
                )
            } catch {
                logger.warning("""
                cloudSourceDeviceId backfill failed during idempotent re-pair: \
                \(error.localizedDescription, privacy: .public)
                """)
            }
        }
        return existing
    }

    /// Wave 6 — companion to `idempotentRePair`. Re-runs the KEM
    /// derivation with the iOS peer's freshly-sent `kemPublicKey` and
    /// the current invitation's `pendingPairingNonce`, then saves the
    /// resulting `PairKey` under the **existing** `PairedDevice`'s
    /// `pairingId`. The HKDF salt is `pairingNonce` (not `pairingId`),
    /// so a new invitation always yields a new secret regardless of
    /// whether the storage id is reused. Storing under the pre-existing
    /// id mirrors iOS's `commitPairedState`, which writes its keychain
    /// entry under `ack.pairingId` — both ends overwrite the same row
    /// with the same secret in lock-step.
    ///
    /// Skipped silently when the iOS peer didn't send KEM material
    /// (legacy build): in that mode encryption is not engaged and the
    /// stale pair-key entry, if any, is never read.
    private func refreshPairKeyForRePair(
        kemPublicKey: Data,
        existingPairingId: UUID
    ) async throws {
        guard
            !kemPublicKey.isEmpty,
            let nonce = pendingPairingNonce
        else { return }
        let derived = try PairKeyDerivation.derive(
            localIdentity: identity,
            peerKEMPublic: kemPublicKey,
            pairingNonce: nonce,
            pairingId: existingPairingId
        )
        try await pairKeyStore.save(derived)
        let fp = pairKeyFingerprint(derived.secret)
        logger.info("""
        PairKey refreshed under existing pairingId=\
        \(existingPairingId, privacy: .public) on idempotent re-pair \
        fp=\(fp, privacy: .public) noncePrefix=\
        \(nonce.prefix(4).map { String(format: "%02x", $0) }.joined(), privacy: .public)
        """)
    }

    /// Surfaces the pair-key orphan that results when `store.add`
    /// fails after the pair-key save succeeded. The protocol doesn't
    /// expose `remove(forPairing:)` yet — overwriting with
    /// `removeAll()` would be far too coarse on production data — so
    /// the recovery path is "the user retries, and a retry overwrites
    /// this entry with a freshly-derived key under the same id" or
    /// "`purgeAllPairings` cleans it up on a future reset". Logging
    /// makes the orphan grep-able instead of invisible.
    func rollbackPairKeyAfterDeviceAddFailure(reason: String) async {
        guard pendingPairingId != nil else { return }
        logger.warning("""
        store.add failed (\(reason, privacy: .public)); \
        pair key for pendingPairingId orphaned until next pair attempt or purge
        """)
    }

    /// PR7 — derives + persists the symmetric pair key when the iOS
    /// peer sent KEM material. Skipped silently for legacy iOS builds
    /// without `kemPublicKey`, so the existing pair flow keeps working
    /// until both sides upgrade.
    func deriveAndSavePairKeyIfNeeded(kemPublicKey: Data) async throws {
        guard
            !kemPublicKey.isEmpty,
            let pairingId = pendingPairingId,
            let nonce = pendingPairingNonce
        else { return }
        let pairKey = try PairKeyDerivation.derive(
            localIdentity: identity,
            peerKEMPublic: kemPublicKey,
            pairingNonce: nonce,
            pairingId: pairingId
        )
        try await pairKeyStore.save(pairKey)
        let fp = pairKeyFingerprint(pairKey.secret)
        logger.info("""
        PairKey persisted (fresh pair) pairingId=\(pairingId, privacy: .public) \
        fp=\(fp, privacy: .public) noncePrefix=\
        \(nonce.prefix(4).map { String(format: "%02x", $0) }.joined(), privacy: .public)
        """)
    }
}
