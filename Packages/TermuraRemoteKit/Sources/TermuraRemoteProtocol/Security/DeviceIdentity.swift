import CryptoKit
import Foundation

/// Long-lived per-device key material. Carries two Curve25519 keypairs:
///   * Ed25519 signing — challenge-response verification during pairing
///     and the source of `deriveDeviceId(from:)` (unchanged from PR1).
///   * X25519 KEM — added in PR7 for HKDF-derived pair-key agreement
///     (`PairKeyDerivation.derive`). Co-exists with Ed25519 instead of
///     replacing it so the existing signing flow + stable deviceId
///     semantics keep working unmodified.
public struct DeviceIdentity: Sendable, Equatable {
    public let publicKeyData: Data
    public let kemPublicKeyData: Data
    private let privateKeyData: Data
    private let kemPrivateKeyData: Data

    private init(
        privateKeyData: Data,
        publicKeyData: Data,
        kemPrivateKeyData: Data,
        kemPublicKeyData: Data
    ) {
        self.privateKeyData = privateKeyData
        self.publicKeyData = publicKeyData
        self.kemPrivateKeyData = kemPrivateKeyData
        self.kemPublicKeyData = kemPublicKeyData
    }

    public static func generate() -> DeviceIdentity {
        let signing = Curve25519.Signing.PrivateKey()
        let kem = Curve25519.KeyAgreement.PrivateKey()
        return DeviceIdentity(
            privateKeyData: signing.rawRepresentation,
            publicKeyData: signing.publicKey.rawRepresentation,
            kemPrivateKeyData: kem.rawRepresentation,
            kemPublicKeyData: kem.publicKey.rawRepresentation
        )
    }

    /// Decodes from the persisted format. PR7 packs both Curve25519 raw
    /// keys back-to-back as `signingPriv (32B) || kemPriv (32B)`. The
    /// store account name is bumped (`device-identity.v2`) so old v1
    /// entries with only the Ed25519 half are ignored on first read.
    public init(privateKey: Data) throws {
        guard privateKey.count == 64 else {
            throw DeviceIdentityError.malformedPersistedKey(byteCount: privateKey.count)
        }
        let signingRaw = privateKey.prefix(32)
        let kemRaw = privateKey.suffix(32)
        let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: signingRaw)
        let kem = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: kemRaw)
        self.init(
            privateKeyData: signing.rawRepresentation,
            publicKeyData: signing.publicKey.rawRepresentation,
            kemPrivateKeyData: kem.rawRepresentation,
            kemPublicKeyData: kem.publicKey.rawRepresentation
        )
    }

    public func sign(_ message: Data) throws -> Data {
        let priv = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        return try priv.signature(for: message)
    }

    public func exportPrivateKeyData() -> Data {
        // 32B signing || 32B KEM. Order is fixed; v2 readers depend on it.
        privateKeyData + kemPrivateKeyData
    }

    /// Performs X25519 key agreement against the peer's KEM public key.
    /// Used by `PairKeyDerivation.derive(...)` to seed HKDF; not invoked
    /// directly from transport code in PR7.
    public func sharedSecret(withPeerKEM peerKEM: Data) throws -> SharedSecret {
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: kemPrivateKeyData)
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKEM)
        return try priv.sharedSecretFromKeyAgreement(with: peer)
    }
}

public enum DeviceIdentityError: Error, Sendable, Equatable {
    /// The persisted blob isn't the v2 64-byte format. Most commonly a
    /// leftover v1 entry from before the X25519 split-out; resetting the
    /// keychain account creates a fresh v2 identity on the next launch.
    case malformedPersistedKey(byteCount: Int)
}

extension DeviceIdentityError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .malformedPersistedKey(byteCount):
            "Persisted device identity is \(byteCount) bytes; expected the 64-byte v2 format. " +
                "Reset the keychain entry to regenerate a fresh identity."
        }
    }
}

public enum DeviceSignature {
    public static func verify(signature: Data, message: Data, publicKey: Data) throws -> Bool {
        let pub = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        return pub.isValidSignature(signature, for: message)
    }
}

public extension DeviceIdentity {
    /// Stable per-device UUID derived from an Ed25519 public key. Surfaced on
    /// the protocol package so the Mac harness and the iOS client both derive
    /// the same id when addressing CloudKit envelopes — a fresh UUID per launch
    /// would orphan in-flight records addressed to the previous id.
    ///
    /// The output is marked as RFC 4122 v5 (name-based, SHA-1 hashed) to keep
    /// the id valid for UUID consumers, even though the digest is SHA-256.
    /// PR7 keeps deriving from the **signing** public key so the deviceId
    /// stays stable across the X25519 keypair addition.
    static func deriveDeviceId(from publicKey: Data) -> UUID {
        let digest = SHA256.hash(data: publicKey)
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
