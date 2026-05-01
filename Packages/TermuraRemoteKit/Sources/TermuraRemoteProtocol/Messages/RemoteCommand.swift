import Foundation

public struct RemoteCommand: Sendable, Codable, Equatable {
    public let commandId: UUID
    public let sessionId: UUID
    public let line: String
    public let issuedAt: Date
    public let clientPreCheck: SafetyVerdict
    /// Set to `true` only after the iPhone user has approved the command via
    /// biometric authentication (Touch ID / Face ID / passcode fallback).
    /// The server uses this as a guard: a `requiresConfirmation` command
    /// without `biometricVerified == true` is rejected outright (defends
    /// against malicious clients omitting the local preflight UI).
    public let biometricVerified: Bool

    public init(
        commandId: UUID = UUID(),
        sessionId: UUID,
        line: String,
        issuedAt: Date = Date(),
        clientPreCheck: SafetyVerdict,
        biometricVerified: Bool = false
    ) {
        self.commandId = commandId
        self.sessionId = sessionId
        self.line = line
        self.issuedAt = issuedAt
        self.clientPreCheck = clientPreCheck
        self.biometricVerified = biometricVerified
    }

    private enum CodingKeys: String, CodingKey {
        case commandId, sessionId, line, issuedAt, clientPreCheck, biometricVerified
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commandId = try container.decode(UUID.self, forKey: .commandId)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        line = try container.decode(String.self, forKey: .line)
        issuedAt = try container.decode(Date.self, forKey: .issuedAt)
        clientPreCheck = try container.decode(SafetyVerdict.self, forKey: .clientPreCheck)
        // Default to `false` so legacy (un-upgraded) clients don't accidentally
        // gain the bypass-prevention privilege.
        biometricVerified = try container.decodeIfPresent(Bool.self, forKey: .biometricVerified) ?? false
    }
}

public struct RemoteCommandCancel: Sendable, Codable, Equatable {
    public let commandId: UUID
    public let reason: String?

    public init(commandId: UUID, reason: String? = nil) {
        self.commandId = commandId
        self.reason = reason
    }
}

public struct RemoteCommandAck: Sendable, Codable, Equatable {
    public let commandId: UUID
    public let acceptedAt: Date

    public init(commandId: UUID, acceptedAt: Date = Date()) {
        self.commandId = commandId
        self.acceptedAt = acceptedAt
    }
}

public struct RemoteConfirmRequest: Sendable, Codable, Equatable {
    public let commandId: UUID
    public let line: String
    public let reason: String

    public init(commandId: UUID, line: String, reason: String) {
        self.commandId = commandId
        self.line = line
        self.reason = reason
    }
}

public struct RemoteConfirmResponse: Sendable, Codable, Equatable {
    public let commandId: UUID
    public let approved: Bool
    public let respondedAt: Date

    public init(commandId: UUID, approved: Bool, respondedAt: Date = Date()) {
        self.commandId = commandId
        self.approved = approved
        self.respondedAt = respondedAt
    }
}
