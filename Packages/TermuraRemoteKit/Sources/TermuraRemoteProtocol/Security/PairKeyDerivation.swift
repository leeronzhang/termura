import CryptoKit
import Foundation

/// Pure function that derives the symmetric `PairKey` shared by the Mac
/// and the iOS client. Both peers run this with their own X25519 KEM
/// private key + the peer's KEM public key + the invitation's
/// `pairingNonce`, and arrive at byte-identical `SymmetricKey`s.
///
/// HKDF parameters are pinned here so a future change forces both peers
/// to upgrade in lockstep — the `info` string already carries a `v2`
/// suffix to leave room for that.
public enum PairKeyDerivation {
    public enum Error: Swift.Error, Sendable, Equatable {
        case missingKEMMaterial
        case missingPairingNonce
        case keyAgreementFailed
    }

    /// HKDF `info` parameter. Carries a version suffix so we can rotate
    /// the KDF without colliding with previously-derived keys.
    public static let infoString = "termura.remote.pair.v2"

    /// Output length matches `ChaChaPoly` / `AES-GCM` 256-bit keys so
    /// future encryption work can adopt the result without re-derivation.
    public static let outputByteCount = 32

    /// Derives the `PairKey` for one specific pairing event.
    ///
    /// - Parameters:
    ///   - localIdentity: this device's full identity (provides the X25519
    ///     KEM private key for `sharedSecretFromKeyAgreement(with:)`).
    ///   - peerKEMPublic: the peer's X25519 KEM public key, taken from
    ///     either `PairingInvitation.kemPublicKey` (iOS side) or
    ///     `PairingChallengeResponse.kemPublicKey` (Mac side).
    ///   - pairingNonce: 16-byte salt the Mac put in the invitation.
    ///   - pairingId: id under which both peers persist the result.
    public static func derive(
        localIdentity: DeviceIdentity,
        peerKEMPublic: Data,
        pairingNonce: Data,
        pairingId: UUID
    ) throws -> PairKey {
        guard !peerKEMPublic.isEmpty else { throw Error.missingKEMMaterial }
        guard !pairingNonce.isEmpty else { throw Error.missingPairingNonce }
        let shared: SharedSecret
        do {
            shared = try localIdentity.sharedSecret(withPeerKEM: peerKEMPublic)
        } catch {
            throw Error.keyAgreementFailed
        }
        let derived = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: pairingNonce,
            sharedInfo: Data(infoString.utf8),
            outputByteCount: outputByteCount
        )
        return PairKey(pairingId: pairingId, secret: derived)
    }
}
