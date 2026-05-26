import Foundation
@testable import Termura
import Testing

/// Regression coverage for `TabManager.focusPane(holding:)`, the seam that fixes the
/// dual-pane bug where a file/image dropped on a pane delivered to that pane's PTY but
/// left keyboard/composer focus elsewhere — so a following cmd-k composer submitted to
/// the wrong terminal and the typed text appeared to vanish.
@MainActor
@Suite("TabManager: focusPane(holding:)")
struct TabManagerFocusPaneTests {
    private func makeSplitManager() -> (TabManager, CommandRouter, MockSessionStore, left: SessionID, right: SessionID) {
        let left = SessionID(rawValue: UUID())
        let right = SessionID(rawValue: UUID())
        let manager = TabManager()
        let router = CommandRouter()
        let store = MockSessionStore()
        manager.inject(sessionStore: store, commandRouter: router)
        let split = ContentTab.split(left: left, right: right, leftTitle: "L", rightTitle: "R")
        manager.terminalItems = [split]
        manager.selectedContentTab = split
        manager.focusedSlot = .left
        return (manager, router, store, left, right)
    }

    @Test("Happy path: focusing the other pane shifts slot, router id, and active session")
    func dropFocusesOtherPane() {
        let (manager, router, store, _, right) = makeSplitManager()

        let shifted = manager.focusPane(holding: right)

        #expect(shifted)
        #expect(manager.focusedSlot == .right)
        #expect(router.focusedDualPaneID == right)
        #expect(store.activeSessionID == right)
    }

    @Test("Guard: with the composer open on a different pane, focus does not shift")
    func composerOpenOnOtherPaneBlocksShift() {
        let (manager, router, store, _, right) = makeSplitManager()
        router.showComposer = true
        router.focusedDualPaneID = nil
        store.activateSession(id: SessionID(rawValue: UUID())) // sentinel, must stay untouched
        let sentinel = store.activeSessionID

        let shifted = manager.focusPane(holding: right)

        #expect(!shifted)
        #expect(manager.focusedSlot == .left)
        #expect(router.focusedDualPaneID == nil)
        #expect(store.activeSessionID == sentinel)
    }

    @Test("Guard allows re-focusing the already-focused pane while the composer is open")
    func composerOpenOnSamePaneStillActivates() {
        let (manager, router, store, left, _) = makeSplitManager()
        router.showComposer = true

        let shifted = manager.focusPane(holding: left)

        #expect(shifted)
        #expect(manager.focusedSlot == .left)
        #expect(router.focusedDualPaneID == left)
        #expect(store.activeSessionID == left)
    }

    @Test("Error path: a session in neither pane is ignored")
    func unknownSessionIsIgnored() {
        let (manager, router, _, _, _) = makeSplitManager()
        router.focusedDualPaneID = nil

        let shifted = manager.focusPane(holding: SessionID(rawValue: UUID()))

        #expect(!shifted)
        #expect(manager.focusedSlot == .left)
        #expect(router.focusedDualPaneID == nil)
    }

    @Test("Lifecycle: not in split mode is a no-op")
    func notInSplitModeIsNoOp() {
        let manager = TabManager()
        let router = CommandRouter()
        let store = MockSessionStore()
        manager.inject(sessionStore: store, commandRouter: router)
        // No split tab selected → resolvedSelectedTab is not a .split.

        let shifted = manager.focusPane(holding: SessionID(rawValue: UUID()))

        #expect(!shifted)
        #expect(router.focusedDualPaneID == nil)
    }
}
