import Foundation

/// On-wire representation of a single encrypted CloudKit envelope.
/// Carries everything `CloudEnvelopeCrypto.open` needs to authenticate
/// and decrypt without consulting the surrounding `CKRecord` plaintext
/// metadata: the AEAD nonce + tag, the ciphertext, and the `keyId`
/// that points at the right `PairKey` in the local store.
///
/// Plaintext duplication of `keyId` exists at the CKRecord level too
/// (`CloudKitSchema.Field.keyId`) so a reader can drop a record before
/// running ChaChaPoly on it when it has no matching key.
public struct CipherBlob: Sendable, Codable, Equatable {
    /// 12-byte ChaChaPoly nonce. Generated fresh per `seal` call.
    public let nonce: Data
    /// Encrypted envelope payload (the codec-encoded `Envelope` blob).
    public let ciphertext: Data
    /// 16-byte ChaChaPoly authentication tag.
    public let tag: Data
    /// `pairingId` of the `PairKey` used to seal the blob. Used to look
    /// up the same key on the receiving side.
    public let keyId: UUID

    public init(nonce: Data, ciphertext: Data, tag: Data, keyId: UUID) {
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
        self.keyId = keyId
    }
}
