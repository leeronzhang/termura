import Foundation

public struct RemoteError: Sendable, Codable, Equatable, Error {
    public enum Code: String, Sendable, Codable, Equatable {
        case versionIncompatible = "version_incompatible"
        case protocolVersionTooOld = "protocol_version_too_old"
        case protocolVersionTooNew = "protocol_version_too_new"
        case codecMismatch = "codec_mismatch"
        case handshakeViolation = "handshake_violation"
        case policyMismatch = "policy_mismatch"
        case unauthorized
        case pairingExpired = "pairing_expired"
        case sessionNotFound = "session_not_found"
        case commandRejected = "command_rejected"
        case payloadTooLarge = "payload_too_large"
        case internalFailure = "internal_failure"
    }

    public let code: Code
    public let message: String
    public let relatedId: UUID?

    public init(code: Code, message: String, relatedId: UUID? = nil) {
        self.code = code
        self.message = message
        self.relatedId = relatedId
    }
}
