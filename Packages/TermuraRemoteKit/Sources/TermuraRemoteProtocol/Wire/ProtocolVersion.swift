import Foundation

public struct ProtocolVersion: Sendable, Codable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// 1.0 → 1.1: PTY byte-stream pipeline (`.ptyStreamSubscribe /
    /// .ptyStreamUnsubscribe / .ptyStreamChunk / .ptyStreamCheckpoint`)
    /// gated by `PeerCapabilities.ptyStream`.
    ///
    /// 1.1 → 1.2: `.ptyResize` envelope so iOS clients can forward
    /// their local reflow to the Mac PTY. Gated by
    /// `PeerCapabilities.ptyResize`; older Mac peers continue to work
    /// because iOS only sends the envelope when the capability is
    /// derived from the peer's announced version.
    ///
    /// 1.2 → 1.3: structured agent-conversation events
    /// (`.agentEventSubscribe / .agentEventUnsubscribe / .agentEvent
    /// / .agentEventCheckpoint`) so iOS renders Claude Code dialogue
    /// with native SwiftUI components instead of a vt terminal. Mac
    /// derives events from Claude Code's transcript JSONL. Gated by
    /// `PeerCapabilities.agentEvents`; older peers stay on the PTY
    /// stream path which remains supported as a Debug fallback.
    ///
    /// `minimumSupported` stays at 1.0 so 1.0 peers continue to
    /// connect — they just never see newer envelope kinds because
    /// capability gates are additive (`version >= X`).
    public static let current = ProtocolVersion(major: 1, minor: 3)

    public static let minimumSupported = ProtocolVersion(major: 1, minor: 0)

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        return lhs.minor < rhs.minor
    }

    public var description: String { "\(major).\(minor)" }
}

public enum VersionCompatibility: Sendable, Equatable {
    case compatible
    case remoteTooOld(minimumRequired: ProtocolVersion)
    case remoteTooNew(maximumSupported: ProtocolVersion)
}

public struct VersionNegotiator: Sendable {
    public let local: ProtocolVersion
    public let minimumAccepted: ProtocolVersion

    public init(local: ProtocolVersion = .current, minimumAccepted: ProtocolVersion = .minimumSupported) {
        self.local = local
        self.minimumAccepted = minimumAccepted
    }

    public func evaluate(remote: ProtocolVersion) -> VersionCompatibility {
        if remote < minimumAccepted {
            return .remoteTooOld(minimumRequired: minimumAccepted)
        }
        if remote.major > local.major {
            return .remoteTooNew(maximumSupported: local)
        }
        return .compatible
    }
}
