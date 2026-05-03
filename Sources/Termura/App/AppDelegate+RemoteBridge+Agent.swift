// Wave 8 — agent-event helpers extracted from
// `AppDelegate+RemoteBridge.swift` to keep that file under the
// file_length budget. Lifecycle-wise these are static
// `@MainActor` helpers wired into the `LiveRemoteSessionsAdapter`
// closure parameter list at adapter construction time; they do not
// own any state of their own.

import Foundation

extension AppDelegate {
    /// Wave 8 — registers the agent-event source factory's cwd
    /// resolver against the active coordinator so a Termura
    /// `SessionID` can be mapped to its working directory (the
    /// directory Claude Code uses to derive its transcript path).
    /// Idempotent on repeat calls.
    @MainActor
    static func installAgentEventSourceFor(coordinator: ProjectCoordinator) {
        HarnessBootstrap.installAgentEventSource { [weak coordinator] sessionId in
            guard let scope = coordinator?.activeContext?.sessionScope else { return nil }
            let id = SessionID(rawValue: sessionId)
            return scope.store.sessions.first(where: { $0.id == id })?.workingDirectory
        }
    }

    /// Wave 8 — agent-event subscribe. The live source lives in the
    /// private harness module (paid feature) and is wired through
    /// `HarnessBootstrap.currentAgentEventSource()`. Returns `nil`
    /// in Free builds / when no transcript resolves to the session,
    /// which the router treats as "no agent stream available".
    @MainActor
    static func subscribeAgentEvents(
        coordinator _: ProjectCoordinator?,
        sessionId: UUID,
        sinceEventId: UUID?
    ) async -> AgentEventSubscription? {
        guard let source = HarnessBootstrap.currentAgentEventSource() else {
            return nil
        }
        return await source.subscribe(sessionId: sessionId, sinceEventId: sinceEventId)
    }

    /// Wave 8 — agent-event unsubscribe. Idempotent. No-op when no
    /// source is installed (Free build) or the subscription was
    /// already torn down (channel close ran first).
    @MainActor
    static func unsubscribeAgentEvents(
        coordinator _: ProjectCoordinator?,
        sessionId: UUID,
        subscriptionId: UUID
    ) async {
        guard let source = HarnessBootstrap.currentAgentEventSource() else { return }
        await source.unsubscribe(sessionId: sessionId, subscriptionId: subscriptionId)
    }
}
