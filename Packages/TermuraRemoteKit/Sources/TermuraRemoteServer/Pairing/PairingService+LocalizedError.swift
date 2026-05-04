import Foundation

extension PairingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noPendingInvitation:
            "No pending pairing invitation. Generate a fresh invitation on the Mac and try again."
        case .tokenMismatch:
            "Pairing token doesn't match. Generate a fresh invitation and try again."
        case .tokenExpired:
            "Pairing invitation has expired. Generate a fresh one (each lasts 5 minutes)."
        case .signatureInvalid:
            "Pairing signature failed verification. Re-issue the invitation."
        case let .alreadyPaired(deviceId):
            "Device \(deviceId.uuidString) is already paired."
        case let .revokeAllFailed(failed):
            "\(failed.count) device(s) could not be revoked. Try again or remove them individually."
        }
    }
}
