// Public protocol surface for the iOS remote-control feature. Always compiled.
// Real implementation lives in `termura-harness/Sources/Remote/` and is gated by
// HARNESS_ENABLED. When that flag is absent (Free build), `RemoteIntegrationFactory`
// returns `NullRemoteIntegration`, so call sites compile and run without changes.

import Foundation
import TermuraRemoteProtocol

protocol RemoteIntegration: Sendable {
    func start() async throws
    func stop() async
    func issueInvitation() async throws -> PairingInvitation
    /// Called by the AppDelegate's `didReceiveRemoteNotification` hook so the
    /// CloudKit transport can poll its inbox immediately instead of waiting
    /// for the next interval tick.
    func notifyPushReceived() async
    /// All paired devices (active and revoked) sorted by `pairedAt` ascending.
    /// Returns `[]` when no harness or pairing yet occurred.
    func listPairedDevices() async throws -> [PairedDeviceSummary]
    /// Marks the device as revoked. Subsequent envelopes from that device id
    /// are rejected by the router. Idempotent for already-revoked ids.
    func revokePairedDevice(id: UUID) async throws
    /// Recent audit entries, newest first, capped at the store's window
    /// (currently 500 entries). Returns `[]` when no harness.
    func auditLog() async throws -> [RemoteAuditEntry]
    var isRunning: Bool { get async }
}

protocol RemoteSessionsAdapter: Sendable {
    func listSessions() async -> [RemoteSessionInfo]
    func executeCommand(line: String, sessionId: UUID) async throws -> CommandRunResult
}

struct CommandRunResult: Sendable, Equatable {
    let stdout: String
    let exitCode: Int32?

    init(stdout: String, exitCode: Int32? = nil) {
        self.stdout = stdout
        self.exitCode = exitCode
    }
}

struct RemoteSessionInfo: Sendable, Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let workingDirectory: String?
    let lastActivityAt: Date
}

// `PairedDeviceSummary`, `RemoteAuditEntry`, and `RemoteAuditOutcome` are
// imported from `TermuraRemoteProtocol` — defined there so the harness
// implementation, the audit log store, and the stub all use the same types.

enum RemoteAdapterError: Error, Sendable, Equatable {
    case sessionNotFound
    case noActiveProject
    case integrationDisabled
}

struct NullRemoteIntegration: RemoteIntegration {
    func start() async throws {
        throw RemoteAdapterError.integrationDisabled
    }

    func stop() async {}

    func issueInvitation() async throws -> PairingInvitation {
        throw RemoteAdapterError.integrationDisabled
    }

    func notifyPushReceived() async {}

    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }

    func revokePairedDevice(id _: UUID) async throws {
        throw RemoteAdapterError.integrationDisabled
    }

    func auditLog() async throws -> [RemoteAuditEntry] { [] }

    var isRunning: Bool { get async { false } }
}

struct NullRemoteSessionsAdapter: RemoteSessionsAdapter {
    func listSessions() async -> [RemoteSessionInfo] { [] }

    func executeCommand(line _: String, sessionId _: UUID) async throws -> CommandRunResult {
        throw RemoteAdapterError.integrationDisabled
    }
}

#if !HARNESS_ENABLED
enum RemoteIntegrationFactory {
    static func make(adapter _: any RemoteSessionsAdapter) -> any RemoteIntegration {
        NullRemoteIntegration()
    }
}
#endif
