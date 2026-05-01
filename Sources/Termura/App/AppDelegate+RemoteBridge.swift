import Foundation
import TermuraRemoteProtocol

// Closures captured by `LiveRemoteSessionsAdapter` resolve the active project
// state through these helpers. They live in their own extension to keep
// `AppDelegate.swift` under the 250-line soft cap and to make the boundary
// between "Composition Root wiring" and "Remote-control bridge logic" explicit.
extension AppDelegate {
    /// PR8 Phase 2 — fires the agent ↔ app bridge `start()` from
    /// `applicationDidFinishLaunching`. The bridge is `async`, so we
    /// route through `Task { await … }` (best-effort): app launch
    /// returns immediately and the bridge converges in the background.
    /// Failure is non-fatal — Settings UI still works without the
    /// agent and pairing flows continue via direct LAN/CloudKit.
    @MainActor
    static func startRemoteAgentBridge(_ bridge: any RemoteAgentBridgeLifecycle) {
        Task { await bridge.start() }
    }

    /// PR8 Phase 2 — fires the agent ↔ app bridge `stop()` from
    /// `applicationWillTerminate`. Best-effort: termination does not
    /// block on bridge teardown; the agent process notices the lost
    /// connection and proceeds with its own shutdown timeout.
    @MainActor
    static func stopRemoteAgentBridge(_ bridge: any RemoteAgentBridgeLifecycle) {
        Task { await bridge.stop() }
    }

    /// PR10 Step 3 — schedules `reinstallIfNeeded()` from
    /// `applicationDidFinishLaunching`. The controller's contract is
    /// to no-op when `isEnabled == false`, so the call is safe to
    /// fire unconditionally; we still gate on the same env flag as
    /// the bridge start so test/UI-test runs opt out together. Best-
    /// effort: a failure here surfaces in the controller's
    /// `lastError` for the next time the user opens Settings, but it
    /// must not block app launch.
    @MainActor
    static func scheduleReinstallIfNeeded(controller: RemoteControlController) {
        Task { await controller.reinstallIfNeeded() }
    }

    /// Fires `restoreIfEnabled()` from `applicationDidFinishLaunching` so
    /// the harness server / router / broadcast subscription come back
    /// online when the user previously turned remote control on. The
    /// controller's contract is to no-op when `isEnabled == false`, so
    /// the call is safe to fire unconditionally; the env-flag gate at
    /// the call site keeps test/UI-test runs opted out alongside the
    /// bridge start. Best-effort: a failure here surfaces in the
    /// controller's `lastError` for the next time the user opens
    /// Settings, but it must not block app launch.
    @MainActor
    static func restoreRemoteIntegration(controller: RemoteControlController) {
        Task { await controller.restoreIfEnabled() }
    }

    /// Builds the live adapter that bridges the active project's `SessionStore`
    /// to the harness router. The `changeStream` is the push-on-change seam
    /// fed by `SessionListBroadcaster` (which holds the paired Continuation);
    /// the harness consumes it via `RemoteSessionsAdapter.sessionListChanges()`.
    /// Static + closure-captured `coordinator` weak ref keeps the adapter
    /// Sendable.
    @MainActor
    static func makeRemoteAdapter(
        coordinator: ProjectCoordinator,
        changeStream: AsyncStream<Void>
    ) -> LiveRemoteSessionsAdapter {
        LiveRemoteSessionsAdapter(
            listProvider: { [weak coordinator] in
                Self.gatherActiveSessions(coordinator: coordinator)
            },
            commandRunner: { [weak coordinator] line, sessionId in
                try await Self.runRemoteCommand(coordinator: coordinator, line: line, sessionId: sessionId)
            },
            changeStream: changeStream,
            screenCapturer: { [weak coordinator] sessionId in
                Self.captureRemoteScreen(coordinator: coordinator, sessionId: sessionId)
            }
        )
    }

    @MainActor
    static func gatherActiveSessions(coordinator: ProjectCoordinator?) -> [RemoteSessionInfo] {
        guard let scope = coordinator?.activeContext?.sessionScope else { return [] }
        return scope.store.sessions.map { record in
            RemoteSessionInfo(
                id: record.id.rawValue,
                title: record.title,
                workingDirectory: record.workingDirectory,
                lastActivityAt: record.lastActiveAt
            )
        }
    }

    /// Snapshot the visible viewport of `sessionId` for the remote-screen
    /// push pulse. Returns `nil` for unknown sessions, no active project,
    /// or engines without a live surface — callers (the harness router's
    /// per-subscription pulse) treat `nil` as "skip this tick" so the
    /// stream resumes once the engine attaches.
    @MainActor
    static func captureRemoteScreen(
        coordinator: ProjectCoordinator?,
        sessionId: UUID
    ) -> ScreenFramePayload? {
        guard let scope = coordinator?.activeContext?.sessionScope else { return nil }
        let id = SessionID(rawValue: sessionId)
        guard let engine = scope.engines.engine(for: id),
              let snapshot = engine.readVisibleScreen()
        else { return nil }
        return ScreenFramePayload(
            sessionId: sessionId,
            rows: snapshot.rows,
            cols: snapshot.cols,
            lines: snapshot.lines
        )
    }

    @MainActor
    static func runRemoteCommand(
        coordinator: ProjectCoordinator?,
        line: String,
        sessionId: UUID
    ) async throws -> CommandRunResult {
        guard let context = coordinator?.activeContext else {
            throw RemoteAdapterError.noActiveProject
        }
        let id = SessionID(rawValue: sessionId)
        do {
            let outcome = try await PTYCommandBridge.run(
                line: line,
                sessionId: id,
                commandId: UUID(),
                scope: context.sessionScope,
                commandRouter: context.commandRouter
            )
            if outcome.chunkMatched {
                return CommandRunResult(stdout: outcome.stdout, exitCode: outcome.exitCode)
            }
            // No chunk completed inside the window — typical for REPLs
            // (Claude Code, IRB) and bare shells without OSC 133;D
            // integration. iOS sees the actual terminal content via the
            // live `screenFrame` push (Phase C); this fallback string is
            // a hint surfaced in the cmdAck stdout for clients without
            // live-screen rendering.
            let fallback = "Command dispatched. See the Mac terminal screen for live output."
            return CommandRunResult(stdout: fallback, exitCode: outcome.exitCode)
        } catch PTYCommandBridge.Failure.sessionNotFound {
            throw RemoteAdapterError.sessionNotFound
        } catch PTYCommandBridge.Failure.noActiveProject {
            throw RemoteAdapterError.noActiveProject
        }
    }
}
