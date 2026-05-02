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
            },
            ptySubscriber: { [weak coordinator] sessionId in
                await Self.subscribePtyStream(coordinator: coordinator, sessionId: sessionId)
            },
            ptyUnsubscriber: { [weak coordinator] sessionId, subscriptionId in
                await Self.unsubscribePtyStream(
                    coordinator: coordinator,
                    sessionId: sessionId,
                    subscriptionId: subscriptionId
                )
            },
            checkpointProvider: { [weak coordinator] sessionId, seq in
                Self.currentPtyCheckpoint(coordinator: coordinator, sessionId: sessionId, seq: seq)
            }
        )
    }

    @MainActor
    static func gatherActiveSessions(coordinator: ProjectCoordinator?) -> [RemoteSessionInfo] {
        guard let scope = coordinator?.activeContext?.sessionScope else { return [] }
        return scope.store.sessions.compactMap { record in
            // Drop sessions without a live engine so iOS never lands on
            // `RemoteCommandRunner`'s 30s timeout for a dead PTY (see
            // `LibghosttyEngine.send` short-circuit on `surface == nil`).
            guard let engine = scope.engines.engine(for: record.id), engine.isRunning else { return nil }
            return RemoteSessionInfo(
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
        guard let engine = scope.engines.engine(for: id) else { return nil }
        // Skip capture for exited / terminating engines. The styled and
        // plain-text paths both gate on `ghosttyView.surface != nil`, so
        // they would silently return nil anyway — this guard makes the
        // intent explicit and keeps the pulse from spending work on a
        // session that's about to be filtered from the iOS list (see
        // `gatherActiveSessions`).
        guard engine.isRunning else { return nil }
        // Prefer the styled snapshot so iOS renders fg/bg/bold/etc. with
        // fidelity. Wave-Styled-v2 uses ghostty_surface_snapshot_viewport
        // which copies the cell grid + palette into a caller-owned buffer
        // under a brief lock and does NOT call render_state_update, so it
        // does not consume terminal/page/row dirty flags that the host's
        // Metal renderer relies on for incremental redraws (the v1 issue
        // that froze the Mac terminal display every pulse).
        //
        // Falls back to the plain-text path when:
        //   - the surface is not yet live (lazy attach)
        //   - the C snapshot returned an error
        //   - the engine type does not implement structured extraction
        //   - the styled extraction returned an empty viewport
        // `lines` is always populated so older iOS clients still see content.
        if let styled = engine.readVisibleStyledScreen(), !styled.lines.isEmpty {
            return ScreenFramePayload(
                sessionId: sessionId,
                rows: styled.rows,
                cols: styled.cols,
                lines: styled.lines,
                styledLines: styled.styledLines
            )
        }
        guard let plain = engine.readVisibleScreen() else { return nil }
        return ScreenFramePayload(
            sessionId: sessionId,
            rows: plain.rows,
            cols: plain.cols,
            lines: plain.lines
        )
    }

    /// Subscribe to a session's raw PTY byte stream for the harness
    /// pty-stream pump. Returns `nil` for unknown sessions, no active
    /// project, or engines without a live surface — callers (the
    /// harness router's `runPtyStreamPump`) treat `nil` as "session
    /// gone, finish the pump cleanly". Mirrors `captureRemoteScreen`'s
    /// resolution path so both the snapshot and stream paths see the
    /// same engine identity.
    @MainActor
    static func subscribePtyStream(
        coordinator: ProjectCoordinator?,
        sessionId: UUID
    ) async -> PtyByteTap.Subscription? {
        guard let scope = coordinator?.activeContext?.sessionScope else { return nil }
        let id = SessionID(rawValue: sessionId)
        guard let engine = scope.engines.engine(for: id) else { return nil }
        return await engine.subscribeBytes()
    }

    /// Cancel a single pty-byte subscription. Idempotent — unknown ids
    /// are silently ignored so the harness router's unsubscribe /
    /// connectionClosed paths can call us without first checking the
    /// session is still alive.
    @MainActor
    static func unsubscribePtyStream(
        coordinator: ProjectCoordinator?,
        sessionId: UUID,
        subscriptionId: UUID
    ) async {
        guard let scope = coordinator?.activeContext?.sessionScope else { return }
        let id = SessionID(rawValue: sessionId)
        guard let engine = scope.engines.engine(for: id) else { return }
        await engine.unsubscribeBytes(id: subscriptionId)
    }

    /// Build a `PtyStreamCheckpoint` keyframe for `sessionId` at `seq`.
    /// Drives the harness pump's cold-start basis and its 30 s /
    /// 256-chunk resync cadence. Returns `nil` for unknown sessions
    /// or transient extraction failures (caller skips the keyframe and
    /// retries on the next cadence tick).
    @MainActor
    static func currentPtyCheckpoint(
        coordinator: ProjectCoordinator?,
        sessionId: UUID,
        seq: UInt64
    ) -> PtyStreamCheckpoint? {
        guard let scope = coordinator?.activeContext?.sessionScope else { return nil }
        let id = SessionID(rawValue: sessionId)
        guard let engine = scope.engines.engine(for: id) else { return nil }
        return engine.currentCheckpoint(sessionId: sessionId, seq: seq)
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
            let outcome = try await RemoteCommandRunner.run(
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
        } catch RemoteCommandRunner.Failure.sessionNotFound {
            throw RemoteAdapterError.sessionNotFound
        } catch RemoteCommandRunner.Failure.noActiveProject {
            throw RemoteAdapterError.noActiveProject
        }
    }
}
