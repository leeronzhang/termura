import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "CloudKitClientTransport+CipherDecode")

// Cipher-blob decoding lives in its own file so the main
// CloudKitClientTransport stays under the file_length budget. Mirrors
// the server-side `CloudKitTransport+CipherDecode`: same outcome enum,
// same Keychain transient-vs-permanent classification, same Apple
// errSec codes (-25308 / -25293) treated as transient so a record
// arriving before first-unlock survives until the keychain comes
// online.

extension CloudKitClientTransport {
    enum CipherOutcome: Sendable {
        case success(Envelope)
        case terminalDrop
        case transientLeave
    }

    func openCipher(_ blob: CipherBlob) async -> CipherOutcome {
        guard let store = pairKeyStore else {
            logger.warning("CipherBlob received but no PairKeyStore configured; dropping record")
            return .terminalDrop
        }
        let pairKey: PairKey?
        do {
            pairKey = try await store.key(forPairing: blob.keyId)
        } catch {
            logger.warning("PairKey lookup failed for \(blob.keyId, privacy: .public): \(error.localizedDescription)")
            return Self.classifyKeychainError(error)
        }
        guard let pairKey else {
            logger.warning("No PairKey for keyId=\(blob.keyId, privacy: .public); dropping record")
            return .terminalDrop
        }
        do {
            let envelope = try CloudEnvelopeCrypto.open(blob, with: pairKey, codec: codec)
            return .success(envelope)
        } catch {
            logger.warning("CloudEnvelopeCrypto.open failed: \(error.localizedDescription)")
            return .terminalDrop
        }
    }

    /// Same classification as the server-side counterpart: keychain
    /// `errSecInteractionNotAllowed` (-25308) and `errSecAuthFailed`
    /// (-25293) are transient (device locked / first-unlock pending);
    /// any other persistence failure is permanent and the record is
    /// dropped.
    static func classifyKeychainError(_ error: any Error) -> CipherOutcome {
        if let typed = error as? KeychainPairKeyStore.Error {
            switch typed {
            case let .persistenceFailure(code):
                if code == -25308 || code == -25293 {
                    return .transientLeave
                }
                return .terminalDrop
            case .decodingFailure:
                return .terminalDrop
            }
        }
        return .terminalDrop
    }
}
