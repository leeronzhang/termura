import CryptoKit
import Foundation

/// Symmetric key shared by the Mac and the iOS client for one specific
/// pairing relationship. Both peers derive it independently during the
/// pair handshake and persist it under the same `pairingId`.
///
/// PR7 only stores the key — it doesn't yet apply it to CloudKit
/// envelopes. That wiring lands in a follow-up step.
public struct PairKey: Sendable, Equatable {
    public let pairingId: UUID
    public let secret: SymmetricKey

    public init(pairingId: UUID, secret: SymmetricKey) {
        self.pairingId = pairingId
        self.secret = secret
    }

    public static func == (lhs: PairKey, rhs: PairKey) -> Bool {
        guard lhs.pairingId == rhs.pairingId else { return false }
        return lhs.secret.withUnsafeBytes { lhsBytes in
            rhs.secret.withUnsafeBytes { rhsBytes in
                lhsBytes.elementsEqual(rhsBytes)
            }
        }
    }

    /// Returns the secret as a `Data` blob for persistence. Callers must
    /// keep this opaque — comparison or display goes through `PairKey`.
    public func exportSecretData() -> Data {
        secret.withUnsafeBytes { Data($0) }
    }
}
