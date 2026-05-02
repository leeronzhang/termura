import Foundation

/// Feature capabilities derived from the peer's negotiated `ProtocolVersion`.
///
/// `ProtocolVersion` is the source of truth for "what the peer can speak";
/// `PeerCapabilities` is a convenience derived view that callers consult
/// when deciding whether to send a wire feature that older peers would
/// reject. All capabilities are derived from the version — there is no
/// separate handshake bit to flip — which keeps the negotiation surface
/// flat and removes one class of "version says A, capabilities say B"
/// drift bugs.
///
/// Add a new capability by (1) bumping `ProtocolVersion.current`,
/// (2) introducing a new `PeerCapabilities` flag, and (3) extending
/// `from(version:)` with the gate condition. Old peers continue to work
/// because every gate is `version >= X` — capabilities are additive.
public struct PeerCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Peer supports the raw PTY byte-stream pipeline:
    /// `.ptyStreamSubscribe / .ptyStreamUnsubscribe / .ptyStreamChunk
    /// / .ptyStreamCheckpoint`. Gated on `ProtocolVersion >= 1.1`.
    public static let ptyStream = PeerCapabilities(rawValue: 1 << 0)

    /// Derive the capability set from a peer's protocol version.
    /// Order matters: newer versions accumulate flags from older ones.
    public static func from(version: ProtocolVersion) -> PeerCapabilities {
        var caps: PeerCapabilities = []
        if version >= ProtocolVersion(major: 1, minor: 1) {
            caps.insert(.ptyStream)
        }
        return caps
    }
}
