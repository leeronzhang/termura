import Foundation

public struct ProtocolVersion: Sendable, Codable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static let current = ProtocolVersion(major: 1, minor: 0)

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
