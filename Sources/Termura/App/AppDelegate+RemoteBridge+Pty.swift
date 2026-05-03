// PTY-related helpers extracted from `AppDelegate+RemoteBridge.swift`
// to keep that file under the §6.1 250-line soft budget. Lifecycle-
// wise these are static `@MainActor` helpers wired into the
// `LiveRemoteSessionsAdapter` closure parameter list at adapter
// construction time; they hold no state.

import AppKit
import Foundation
import TermuraRemoteProtocol

extension AppDelegate {
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

    /// Forward an iOS-driven local reflow to the Mac PTY. Routed by
    /// the harness from a `.ptyResize` envelope; `LiveRemoteSessionsAdapter`
    /// captures this static via a closure so the harness module never
    /// references AppKit directly. Fire-and-forget on iOS — no envelope
    /// is shipped back regardless of the returned bool.
    ///
    /// **A2 active-focus guard**: when `NSApp.isActive == true` the Mac
    /// user is in the foreground and we refuse the resize so their
    /// local GhosttyTerminalView width is not changed underneath them
    /// (the same shared PTY backs both views). This is a coarse-grained
    /// signal — it rejects all resizes while the app is frontmost,
    /// not just resizes targeting the same session that has key window
    /// focus — but it's strictly conservative and avoids reaching into
    /// the AppKit window/firstResponder graph for per-session state.
    /// `NSApp` access here is the §3.2 platform-adapter exception.
    @MainActor
    static func resizeRemotePty(
        coordinator: ProjectCoordinator?,
        sessionId: UUID,
        cols: Int,
        rows: Int
    ) async -> Bool {
        guard !NSApp.isActive else { return false }
        guard let scope = coordinator?.activeContext?.sessionScope else { return false }
        let id = SessionID(rawValue: sessionId)
        guard let engine = scope.engines.engine(for: id), engine.isRunning else { return false }
        await engine.resize(
            columns: UInt16(clamping: cols),
            rows: UInt16(clamping: rows)
        )
        return true
    }
}
