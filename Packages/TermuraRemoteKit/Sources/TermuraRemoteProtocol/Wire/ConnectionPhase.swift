import Foundation

/// Per-connection state machine resolving the codec used to encode/decode
/// envelope payloads.
///
/// Phase semantics:
/// - `.handshake`: connection just opened. **All envelopes must be JSON-encoded.**
///   Only pair / error / ping / pong kinds are permitted; anything else is a
///   protocol violation and the connection is closed.
/// - `.active(codec:)`: pairing completed; subsequent envelopes are encoded
///   with the negotiated codec. Receiving an envelope encoded with a different
///   codec is a protocol violation.
public enum ConnectionPhase: Sendable, Equatable {
    case handshake
    case active(CodecKind)

    public var codec: CodecKind {
        switch self {
        case .handshake: .json
        case let .active(kind): kind
        }
    }

    public var isHandshake: Bool {
        if case .handshake = self { return true }
        return false
    }
}

/// Allowed envelope kinds during the handshake phase. Any other kind on a
/// `.handshake` connection is a `RemoteError.handshakeViolation`.
///
/// `.rejoin` / `.rejoinAck` are allowed so an already-paired client can
/// resume a session on a fresh transport channel without re-running the
/// invitation-bound `pairInit` flow. The server validates the rejoin's
/// signature against the persisted paired-device record before flipping
/// the channel to `.active`.
public extension Envelope.Kind {
    var isAllowedDuringHandshake: Bool {
        switch self {
        case .pairInit, .pairComplete, .rejoin, .rejoinAck, .ping, .pong, .error:
            true
        default:
            false
        }
    }
}
