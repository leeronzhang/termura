import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "CloudKitTransport+CipherDecode")

// Cipher-blob decoding lives in its own file so the main CloudKitTransport
// stays under the file_length budget. The actor's `pairKeyStore` and
// `codec` are package-internal so this same-module extension can reuse
// them. The transient-vs-permanent classification on Keychain failures
// is shared with the iOS-side CloudKitClientTransport (Wave 1 §3) so
// both sides leave records in the mailbox during first-unlock instead
// of silently dropping them.

extension CloudKitTransport {
    /// Outcome of trying to open a cipher-blob payload. `.success` lets
    /// dispatch proceed to the router; `.terminalDrop` deletes the
    /// record (key missing / tampered, no future poll will recover);
    /// `.transientLeave` keeps the record in CloudKit but bumps
    /// `lastSeen` past it so the current session won't loop on it.
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
            // Distinguish keychain transient errors (locked, in restore
            // mode) from genuine "key not stored" returns. The
            // PairKeyStore protocol throws a typed error on persistence
            // failure; treat that as transient. A nil-return below is
            // the permanent-drop path.
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
            // ChaChaPoly tag verification failure is permanent: the
            // pair key is wrong or the ciphertext was tampered with.
            // Either way no future poll will recover it.
            logger.warning("CloudEnvelopeCrypto.open failed: \(error.localizedDescription)")
            return .terminalDrop
        }
    }

    /// Maps a `PairKeyStore.key(forPairing:)` thrown error into the
    /// cipher-open outcome. Keychain `errSecInteractionNotAllowed`
    /// (-25308) and `errSecAuthFailed` (-25293) happen when the device
    /// is locked or first-unlock hasn't completed; the right answer is
    /// to leave the record so a later run with an unlocked keychain
    /// can decrypt it. Anything else is treated as a real persistence
    /// failure and the record is dropped to keep the mailbox bounded.
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
