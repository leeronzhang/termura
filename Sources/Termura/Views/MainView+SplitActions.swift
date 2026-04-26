import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "MainView+SplitActions")

// MARK: - Split tab toggle

extension MainView {
    /// Toggles the current terminal tab between single and split (two-pane) mode.
    func toggleSplitTab() {
        tabManager.toggleSplitTab()
        persistOpenTabs()
    }

    /// Dissolves the current split tab into two separate terminal tabs.
    func dissolveSplitTab() {
        tabManager.dissolveSplitTab()
        persistOpenTabs()
    }
}

// MARK: - Pane swap

extension MainView {
    /// Swaps the left and right panes of the current split tab.
    func swapPanes() {
        tabManager.swapPanes()
        persistOpenTabs()
    }
}

// MARK: - Keyboard focus switch

extension MainView {
    /// Focus a specific pane in dual-pane mode via keyboard shortcut (Ctrl+left/right arrow).
    func handleFocusDualPane(_ slot: PaneSlot) {
        tabManager.handleFocusDualPane(slot)
    }
}

// MARK: - Note split actions

extension MainView {
    func toggleNoteSplitTab() {
        tabManager.toggleNoteSplitTab()
        persistOpenTabs()
    }

    func swapNotePanes() {
        tabManager.swapNotePanes()
        persistOpenTabs()
    }

    func handleFocusNoteDualPane(_ slot: PaneSlot) {
        tabManager.handleFocusNoteDualPane(slot)
    }
}

// MARK: - Drag-and-drop pane replacement

extension MainView {
    /// Replaces the session in `slot` with `draggedID` when a session is dragged onto a split pane.
    func handleDropSession(_ draggedID: SessionID, onto slot: PaneSlot) {
        tabManager.handleDropSession(draggedID, onto: slot)
        persistOpenTabs()
    }
}
