// Composition-root observer that pings the harness router whenever the active
// project's session list mutates so iOS clients learn about session opens /
// closes immediately. Sources of change watched here:
//  * `withObservationTracking` re-armed against `activeContext.sessionScope.store.sessions`
//  * `NSWindow.didBecomeKeyNotification` so a switch between project windows
//    (which flips `coordinator.activeContext`) re-broadcasts even when the new
//    store hasn't itself mutated yet.
//
// WHY: pre-fix, Mac never pushed session changes and iOS only pulled at pair /
// reconnect — sessions opened after pairing were invisible. See CLAUDE.md
// §3.6 (no pull-once-on-pair) for the project-wide rule this enforces.
//
// OWNER: AppDelegate creates and retains exactly one instance.
// CANCEL: AppDelegate.applicationWillTerminate calls `stop()`.
// TEARDOWN: `stop()` cancels the observation task and removes the notification
//           observer, leaving no background activity behind.

import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionListBroadcaster")

@MainActor
final class SessionListBroadcaster {
    private weak var coordinator: ProjectCoordinator?
    private let changeContinuation: AsyncStream<Void>.Continuation
    private let snapshotProvider: @MainActor () -> [UUID]
    private var observationTask: Task<Void, Never>?
    private var windowFocusObserver: (any NSObjectProtocol)?
    private var lastSnapshot: [UUID] = []

    /// `snapshotProvider` returns the current "alive session ids" — the
    /// projection iOS sees. Defaults to a raw read of `store.sessions`
    /// for callers that don't need engine-state filtering (tests).
    /// AppDelegate injects a closure that defers to
    /// `gatherActiveSessions(coordinator:)` so engine lifecycle changes
    /// (process exits) become observable here.
    init(
        coordinator: ProjectCoordinator,
        changeContinuation: AsyncStream<Void>.Continuation,
        snapshotProvider: (@MainActor () -> [UUID])? = nil
    ) {
        self.coordinator = coordinator
        self.changeContinuation = changeContinuation
        if let snapshotProvider {
            self.snapshotProvider = snapshotProvider
        } else {
            self.snapshotProvider = { [weak coordinator] in
                coordinator?.activeContext?.sessionScope.store.sessions.map(\.id.rawValue) ?? []
            }
        }
    }

    /// Re-evaluate the alive-session-id snapshot and broadcast if it
    /// differs from the last emission. Called from outside the
    /// `withObservationTracking` loop when state that isn't on the
    /// observation graph mutates — currently `LibghosttyEngine.state`
    /// flipping to `.disposed` after a child process exits. Idempotent:
    /// equal snapshots are dropped without yielding.
    func pingNow() {
        fireIfChanged()
    }

    /// Begin observing. Idempotent — a second call replaces the existing task
    /// so re-installation after a teardown / restart leaves only one observer.
    func start() {
        stop()
        // WHY: a project-window focus switch flips `coordinator.activeContext`
        // to a different store; without this hook iOS would keep showing the
        // previous project's session list until that store happened to mutate.
        // OWNER: this broadcaster — token stored in `windowFocusObserver`.
        // TEARDOWN: `stop()` removes the observer via NotificationCenter.
        // TEST: `SessionListBroadcasterTests.windowFocusFiresBroadcast`
        //       (added alongside this commit).
        windowFocusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireIfChanged() }
        }
        observationTask = Task { @MainActor [weak self] in
            await self?.runObservationLoop()
        }
    }

    /// Cancel the observation and detach the focus notification observer.
    /// Idempotent.
    func stop() {
        observationTask?.cancel()
        observationTask = nil
        if let observer = windowFocusObserver {
            NotificationCenter.default.removeObserver(observer)
            windowFocusObserver = nil
        }
    }

    private func runObservationLoop() async {
        // Initial fire: emit the current snapshot once on startup so a client
        // that paired before any project window opened still gets a fresh
        // (empty) list rather than dangling on the pair-time snapshot.
        fireIfChanged()
        while !Task.isCancelled {
            guard let store = currentStore() else {
                // No active project yet (launcher still up). Sleep briefly
                // and re-poll — `didBecomeKeyNotification` covers the wake
                // when the first window opens, but the polling fallback
                // keeps us responsive if focus arrives via another path.
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                continue
            }
            await Self.waitForChange(in: store)
            fireIfChanged()
        }
    }

    private func currentStore() -> SessionStore? {
        coordinator?.activeContext?.sessionScope.store
    }

    private func fireIfChanged() {
        let snapshot = snapshotProvider()
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        changeContinuation.yield()
        logger.debug("Broadcast trigger: \(snapshot.count) session(s)")
    }

    private static func waitForChange(in store: SessionStore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = store.sessions
            } onChange: {
                continuation.resume()
            }
        }
    }
}
