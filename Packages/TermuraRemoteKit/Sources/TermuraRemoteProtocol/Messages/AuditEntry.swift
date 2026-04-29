import Foundation

/// Public-facing summary of a paired device — exposed to the SwiftUI layer
/// without leaking the internal `PairedDevice` type's storage details.
public struct PairedDeviceSummary: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let nickname: String
    public let pairedAt: Date
    public let revokedAt: Date?

    public init(id: UUID, nickname: String, pairedAt: Date, revokedAt: Date? = nil) {
        self.id = id
        self.nickname = nickname
        self.pairedAt = pairedAt
        self.revokedAt = revokedAt
    }

    public var isActive: Bool { revokedAt == nil }
}

/// Outcome a single command produced after the router applied policy + auth
/// gates. Persisted with `RemoteAuditEntry` so the user can see why an entry
/// was let through, held, or rejected.
public enum RemoteAuditOutcome: Sendable, Codable, Equatable {
    case dispatched
    case awaitingConfirmation
    case rejected(reason: String)
}

/// One row in the user-visible command history. Stored by the audit log
/// (file-backed, capped) and surfaced in the Mac Settings UI.
public struct RemoteAuditEntry: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let deviceId: UUID
    public let line: String
    public let verdict: SafetyVerdict
    public let outcome: RemoteAuditOutcome

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        deviceId: UUID,
        line: String,
        verdict: SafetyVerdict,
        outcome: RemoteAuditOutcome
    ) {
        self.id = id
        self.timestamp = timestamp
        self.deviceId = deviceId
        self.line = line
        self.verdict = verdict
        self.outcome = outcome
    }
}
