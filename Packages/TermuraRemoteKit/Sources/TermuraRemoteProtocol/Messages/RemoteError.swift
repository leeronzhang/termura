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
        /// Wave 4 — Mac has revoked the iPhone (or the iPhone was never
        /// paired with this Mac). Returned in two scenarios:
        ///   * `.rejoin` from a paired-but-now-revoked device, so the
        ///     iOS `RemoteStore.reconnect` path can fail explicitly
        ///     instead of timing out on a hung session-list request.
        ///   * Any business envelope (`cmd_exec` / `sessionListRequest`
        ///     / etc.) from a revoked device, so the iPhone discovers
        ///     the revoke at the next interaction instead of staring
        ///     at a silently broken UI.
        /// iOS surfaces this via `RemoteStore.failWith` with an
        /// action-oriented message that points the user back to
        /// PairingView.
        case devicePeerRevoked = "device_peer_revoked"
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
