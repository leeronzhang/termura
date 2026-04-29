import CryptoKit
import Foundation

/// Encrypts / decrypts CloudKit envelope payloads using ChaChaPoly with
/// a `PairKey` (32-byte symmetric key derived during pairing).
///
/// PR7 wraps every business envelope traversing the CloudKit mailbox
/// in a `CipherBlob`; CloudKit Dashboard / CKAsset eyes only ever see
/// ciphertext + routing metadata. Pair-handshake envelopes that flow
/// through CloudKit *before* both peers hold the same `PairKey` ride
/// in plaintext (a separate record-shape branch — see
/// `CloudKitEnvelopeRecord.Payload`).
public enum CloudEnvelopeCrypto {
    public enum Error: Swift.Error, Sendable, Equatable {
        case sealFailed(reason: String)
        case openFailed(reason: String)
        case codecFailed(reason: String)
    }

    /// Encrypt the envelope. The output `CipherBlob` carries the
    /// `pairKey.pairingId` so the receiver can look up the same key.
    public static func seal(
        envelope: Envelope,
        with pairKey: PairKey,
        codec: any RemoteCodec
    ) throws -> CipherBlob {
        let plaintext: Data
        do {
            plaintext = try codec.encode(envelope)
        } catch {
            throw Error.codecFailed(reason: error.localizedDescription)
        }
        let sealed: ChaChaPoly.SealedBox
        do {
            sealed = try ChaChaPoly.seal(plaintext, using: pairKey.secret)
        } catch {
            throw Error.sealFailed(reason: error.localizedDescription)
        }
        return CipherBlob(
            nonce: Data(sealed.nonce),
            ciphertext: sealed.ciphertext,
            tag: sealed.tag,
            keyId: pairKey.pairingId
        )
    }

    /// Decrypt the envelope. Throws `openFailed` when the AEAD tag
    /// fails to verify (tampering, wrong key, malformed blob) or the
    /// nonce/tag don't match ChaChaPoly's required sizes.
    public static func open(
        _ blob: CipherBlob,
        with pairKey: PairKey,
        codec: any RemoteCodec
    ) throws -> Envelope {
        guard blob.keyId == pairKey.pairingId else {
            throw Error.openFailed(reason: "keyId mismatch (blob=\(blob.keyId), key=\(pairKey.pairingId))")
        }
        let nonce: ChaChaPoly.Nonce
        do {
            nonce = try ChaChaPoly.Nonce(data: blob.nonce)
        } catch {
            throw Error.openFailed(reason: "invalid nonce: \(error.localizedDescription)")
        }
        let sealed: ChaChaPoly.SealedBox
        do {
            sealed = try ChaChaPoly.SealedBox(
                nonce: nonce,
                ciphertext: blob.ciphertext,
                tag: blob.tag
            )
        } catch {
            throw Error.openFailed(reason: "invalid sealed box: \(error.localizedDescription)")
        }
        let plaintext: Data
        do {
            plaintext = try ChaChaPoly.open(sealed, using: pairKey.secret)
        } catch {
            throw Error.openFailed(reason: "tag verification failed")
        }
        do {
            return try codec.decode(Envelope.self, from: plaintext)
        } catch {
            throw Error.codecFailed(reason: error.localizedDescription)
        }
    }
}
