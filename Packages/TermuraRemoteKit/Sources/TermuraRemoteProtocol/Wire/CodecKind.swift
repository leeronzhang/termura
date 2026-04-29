import Foundation

/// Wire codec identifiers exchanged during pairing. Both ends declare the
/// codecs they understand in `PairingInvitation.supportedCodecs` and
/// `PairingChallengeResponse.supportedCodecs`; the server picks the highest
/// priority codec both ends support and writes it into
/// `PairingCompleteAck.negotiatedCodec`.
public enum CodecKind: String, Sendable, Codable, CaseIterable, Equatable {
    case json
    case messagepack
}

public extension CodecKind {
    /// Server-side preference order. Server prefers `messagepack` (smaller,
    /// faster) but always falls back to `json` for legacy clients.
    static let preferredOrder: [CodecKind] = [.messagepack, .json]

    /// Returns the highest-priority codec supported by both peers, or `.json`
    /// as the conservative fallback if no overlap (legacy clients with no
    /// `supportedCodecs` field default to `[.json]`, which always overlaps).
    static func negotiate(
        local: [CodecKind],
        remote: [CodecKind]
    ) -> CodecKind {
        for candidate in preferredOrder where local.contains(candidate) && remote.contains(candidate) {
            return candidate
        }
        return .json
    }
}
