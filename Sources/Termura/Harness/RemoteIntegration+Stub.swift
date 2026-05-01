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
    /// PR9 — marks every active paired device as revoked in one call. Returns
    /// the ids that were successfully revoked (already-revoked entries are
    /// silently skipped and not part of the success list). On partial
    /// persistence failure the underlying harness throws an error carrying
    /// the failed ids; callers may re-`listPairedDevices()` to compute the
    /// success set in that case.
    func revokeAllPairedDevices() async throws -> [UUID]
    /// PR9 — drops every paired-device record and pair-key entry from the
    /// harness-side stores and resets any in-flight pairing handshake. Used
    /// by the resetPairings flow in `RemoteControlController`. Identity,
    /// audit log, and agent-side state (cursor / quarantine) are out of
    /// scope here; the controller orchestrates those separately.
    func resetPairingState() async throws
    /// Recent audit entries, newest first, capped at the store's window
    /// (currently 500 entries). Returns `[]` when no harness.
    func auditLog() async throws -> [RemoteAuditEntry]
    var isRunning: Bool { get async }
}

protocol RemoteSessionsAdapter: Sendable {
    func listSessions() async -> [RemoteSessionInfo]
    func executeCommand(line: String, sessionId: UUID) async throws -> CommandRunResult
    /// Async stream of session-list change pings. Subscribers (e.g. the
    /// harness router) re-fetch via `listSessions()` on every emission and
    /// fan out a fresh `sessionList` envelope to all paired clients. Default
    /// implementation returns an immediately-finished stream so adapters
    /// without a live source (Free build, tests) don't have to opt in.
    /// WHY: pull-once-on-pair leaves iOS stuck on a stale snapshot whenever
    /// the user opens or closes a session on Mac after the initial sync.
    func sessionListChanges() -> AsyncStream<Void>
}

extension RemoteSessionsAdapter {
    func sessionListChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
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
    /// PR9 — `revokeAllPairedDevices()` ran to completion but at least
    /// one device's persistence write failed. Successful revocations
    /// are kept (no rollback); the failed ids are surfaced so the UI
    /// can show "X of Y could not be revoked". Translated from the
    /// kit-internal `PairingError.revokeAllFailed` at the harness
    /// boundary so the controller stays free of `TermuraRemoteServer`
    /// error surface.
    case partialRevokeAllFailed(failed: [UUID])
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

    /// Free build: nothing to revoke (no pairings exist), so return [].
    /// Symmetric with `listPairedDevices()` returning [].
    func revokeAllPairedDevices() async throws -> [UUID] { [] }

    /// Free build: there is no pairing state to clear, but a caller asking
    /// "wipe pairings" without a harness present is almost certainly a
    /// configuration error — surface that explicitly rather than silently
    /// no-op'ing, matching the contract of `start()` / `issueInvitation()`.
    func resetPairingState() async throws {
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

// PR8 Phase 2 — minimal hook surface for the agent ↔ app bridge.
// The Free build sees only this protocol; the harness build supplies a
// concrete implementation through `RemoteIntegrationFactory.makeAgentBridge`.
// `AppDelegate+RemoteBridge.swift` is the single call site and never
// references any harness concrete type.
protocol RemoteAgentBridgeLifecycle: Sendable {
    func start() async
    func stop() async
    /// PR9 — asks the agent process to wipe its own state stores
    /// (cursor + quarantine). Routed via XPC `resetAgentState` RPC by the
    /// harness assembly. Errors propagate so the controller's resetPairings
    /// flow can route to its β-probe + γ-fallback path on RPC failure.
    func resetAgentState() async throws
}

struct NullRemoteAgentBridgeLifecycle: RemoteAgentBridgeLifecycle {
    func start() async {}
    func stop() async {}
    /// Free build has no agent process to reset; treat as no-op so the
    /// resetPairings happy path stays clean when the harness isn't wired.
    func resetAgentState() async throws {}
}

#if !HARNESS_ENABLED
enum RemoteIntegrationFactory {
    static func make(adapter _: any RemoteSessionsAdapter) -> any RemoteIntegration {
        NullRemoteIntegration()
    }

    static func makeAgentBridge(integration _: any RemoteIntegration) -> any RemoteAgentBridgeLifecycle {
        NullRemoteAgentBridgeLifecycle()
    }
}
#endif
