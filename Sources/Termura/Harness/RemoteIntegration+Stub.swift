// Public protocol surface for the iOS remote-control feature. Always compiled.
// Real implementation lives in the paid harness module and is gated by
// HARNESS_ENABLED. Public callers go through `RemoteIntegrationLauncher` (defined
// below); when HARNESS_ENABLED is absent (Free build), the launcher returns
// `NullRemoteIntegration`, so call sites compile and run without changes.

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
    /// Snapshot the current visible viewport of `sessionId` as a
    /// `ScreenFramePayload`. Returns `nil` when the session no longer
    /// exists or there is no active project. Drives the harness
    /// `.screenFrame` push pulse so iOS can render REPL output that
    /// otherwise wouldn't reach the cmdExec stdout fallback (Claude Code
    /// and other interactive tools that don't emit OSC 133;D markers).
    /// Default implementation returns `nil` so adapters without a live
    /// source (Free build, tests) compile without changes.
    func captureScreen(sessionId: UUID) async -> ScreenFramePayload?

    /// Subscribe to a session's raw PTY byte stream so the harness
    /// router's pty-stream pump can ship `.ptyStreamChunk` envelopes to
    /// iOS. The returned `Subscription.stream` yields `Data` chunks as
    /// the IO callback receives them; the router's pump coalesces them
    /// per `PtyStreamPolicy` before shipping.
    ///
    /// Returns `nil` for unknown sessions, sessions without a live
    /// engine, or builds without a live source (Free build, tests).
    /// Default implementation returns `nil`.
    func subscribePty(sessionId: UUID) async -> PtyByteTap.Subscription?

    /// Cancel a previously-issued pty-byte subscription. Idempotent;
    /// unknown ids are silently ignored. The router calls this on
    /// `.ptyStreamUnsubscribe`, on `connectionClosed`, and on duplicate-
    /// subscribe replacement. Default is a no-op.
    func unsubscribePty(sessionId: UUID, subscriptionId: UUID) async

    /// Build a `PtyStreamCheckpoint` keyframe for the current viewport
    /// of `sessionId`. The router calls this once at subscribe-time
    /// (cold-start basis) and again on its periodic 30 s / 256-chunk
    /// resync cadence. Returns `nil` for unknown sessions or transient
    /// extraction failures. Default implementation returns `nil`.
    func currentCheckpoint(sessionId: UUID, seq: UInt64) async -> PtyStreamCheckpoint?

    /// Forward an iOS-driven local reflow to the Mac PTY so the
    /// upstream shell / REPL re-emits output at the new column count
    /// and the iOS canvas stops re-folding bytes that Mac auto-wrapped
    /// at a different width.
    ///
    /// Returns `true` when the Mac engine accepted and resized;
    /// `false` when rejected (Mac user is active per the A2 guard,
    /// session has no live engine, no active project, or builds
    /// without a live source). The router uses the bool only for
    /// observability; iOS treats the call as fire-and-forget.
    /// Default returns `false` so Free build / tests safely no-op.
    func resizePty(sessionId: UUID, cols: Int, rows: Int) async -> Bool

    /// Wave 8 — subscribe to structured agent-conversation events
    /// (Claude Code transcript JSONL). Returns nil for sessions with
    /// no resolvable transcript or builds without a live source.
    /// `sinceEventId` is the resume cursor.
    func subscribeAgentEvents(
        sessionId: UUID,
        sinceEventId: UUID?
    ) async -> AgentEventSubscription?

    /// Cancel an agent-event subscription. Idempotent.
    func unsubscribeAgentEvents(sessionId: UUID, subscriptionId: UUID) async
}

extension RemoteSessionsAdapter {
    func sessionListChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func captureScreen(sessionId _: UUID) async -> ScreenFramePayload? { nil }
    func subscribePty(sessionId _: UUID) async -> PtyByteTap.Subscription? { nil }
    func unsubscribePty(sessionId _: UUID, subscriptionId _: UUID) async {}
    func currentCheckpoint(sessionId _: UUID, seq _: UInt64) async -> PtyStreamCheckpoint? { nil }
    func resizePty(sessionId _: UUID, cols _: Int, rows _: Int) async -> Bool { false }
    func subscribeAgentEvents(sessionId _: UUID, sinceEventId _: UUID?) async -> AgentEventSubscription? { nil }
    func unsubscribeAgentEvents(sessionId _: UUID, subscriptionId _: UUID) async {}
}

// `AgentEventSubscription` + `AgentEventSource` live in
// `AgentEventSource.swift` to keep this file under the file_length
// budget.

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
    /// PR9 — `revokeAll` partial failure: surviving successes are kept
    /// (no rollback), failed ids surface so the UI can show "X of Y could
    /// not be revoked". Translated from kit-internal `PairingError.revokeAllFailed`.
    case partialRevokeAllFailed(failed: [UUID])
    case macSurfaceUnavailable
}

extension RemoteAdapterError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            "Session not found."
        case .noActiveProject:
            "Open a project before performing this remote action."
        case .integrationDisabled:
            "Remote integration is not available in this build."
        case let .partialRevokeAllFailed(failed):
            "\(failed.count) device(s) could not be revoked."
        case .macSurfaceUnavailable:
            "Mac terminal isn't visible. Bring the Termura window to the front and retry."
        }
    }
}

/// Free build: every mutating op throws `.integrationDisabled`;
/// every read returns the empty answer.
/// `revokeAll`/`auditLog` parallel `listPairedDevices()` (empty);
/// `resetPairingState` throws explicitly so a caller asking to "wipe
/// pairings" without a harness gets the same signal as `start()`.
struct NullRemoteIntegration: RemoteIntegration {
    func start() async throws { throw RemoteAdapterError.integrationDisabled }
    func stop() async {}
    func issueInvitation() async throws -> PairingInvitation { throw RemoteAdapterError.integrationDisabled }
    func notifyPushReceived() async {}
    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }
    func revokePairedDevice(id _: UUID) async throws { throw RemoteAdapterError.integrationDisabled }
    func revokeAllPairedDevices() async throws -> [UUID] { [] }
    func resetPairingState() async throws { throw RemoteAdapterError.integrationDisabled }
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
// concrete implementation through `RemoteIntegrationLauncher.makeAgentBridge`.
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

/// Free build: no agent process to reset; resetAgentState is a no-op
/// so resetPairings happy path stays clean when harness isn't wired.
struct NullRemoteAgentBridgeLifecycle: RemoteAgentBridgeLifecycle {
    func start() async {}
    func stop() async {}
    func resetAgentState() async throws {}
}

/// Public façade callers go through. After Wave 1 it dispatches via
/// closures registered in `HarnessBootstrap` rather than `#if`-routed
/// to a private-impl type name. The harness build wires real factories
/// inside its `install()`; the Free build leaves the closures `nil` so
/// the Null fallbacks below take over. Non-stub public files (e.g.
/// `AppDelegate.swift`) never reference a private-impl symbol.
@MainActor
enum RemoteIntegrationLauncher {
    static func make(adapter: any RemoteSessionsAdapter) -> any RemoteIntegration {
        if let factory = HarnessBootstrap.currentIntegrationFactory() {
            return factory(adapter)
        }
        return NullRemoteIntegration()
    }

    static func makeAgentBridge(integration: any RemoteIntegration) -> any RemoteAgentBridgeLifecycle {
        if let factory = HarnessBootstrap.currentAgentBridgeFactory() {
            return factory(integration)
        }
        return NullRemoteAgentBridgeLifecycle()
    }
}
