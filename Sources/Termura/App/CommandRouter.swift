import Foundation
import Observation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "CommandRouter")

/// Type-safe command router replacing NotificationCenter for menu → view communication.
/// Owned per-project by `ProjectContext`; injected via `@Environment(\.commandRouter)`.
@Observable @MainActor
final class CommandRouter {
    // MARK: - Sheet presentation

    var showSearch = false
    var showNotes = false
    var showHarness = false
    var showBranchMerge = false
    /// Non-nil triggers export sheet for the specified session.
    var exportSessionID: SessionID?

    // MARK: - Sidebar

    var showSidebar = true
    /// The currently selected sidebar tab. Owned here so tab switches triggered by
    /// toggleComposerNotes() update atomically with isComposerNotesActive in one
    /// SwiftUI render pass, preventing the one-frame notesEmptyState flash.
    var selectedSidebarTab: SidebarTab = .sessions
    /// The sidebar tab to restore when composer notes mode is deactivated.
    var tabBeforeComposer: SidebarTab?
    /// True when the sidebar was auto-revealed for composer notes mode and should
    /// be re-hidden when notes mode exits. Cleared if the user manually toggles
    /// the sidebar while notes mode is active.
    var sidebarWasHiddenForNotes = false

    // MARK: - Commands (consumed by MainView via a single reduce step)

    /// Pending command for MainView to process. Cleared by MainView after handling.
    /// All command-driven side-effects funnel through here to avoid concurrent .onChange races.
    var pendingCommand: PendingCommand?

    // MARK: - Dual pane

    /// Whether dual-pane (side-by-side) mode is active. Toolbar reads this for visual state.
    var isDualPaneActive = false
    /// Tracks which pane was last clicked in dual-pane mode (set by NSEvent monitors).
    var focusedDualPaneID: SessionID?
    /// Whether the session-info metadata panel is visible in dual-pane mode.
    /// Toggled by the info toolbar button; applies globally (not per-pane).
    var showDualPaneMetadata = true

    // MARK: - Note dual pane

    /// Whether note dual-pane (side-by-side) mode is active.
    var isNoteDualPaneActive = false
    /// Which pane is currently focused in note dual-pane mode.
    var focusedNotePaneSlot: PaneSlot = .left

    // MARK: - Per-terminal toggles

    var showComposer: Bool = false

    /// Closure injected by TerminalAreaView to insert text into the active Composer editor.
    /// Non-nil only while the Composer is open; cleared on dismiss.
    var composerInsertHandler: ((String) -> Void)?

    /// True while the composer notes toggle is active (sidebar is showing notes via the button).
    /// SidebarView observes this directly via `.onChange(of:)`.
    var isComposerNotesActive = false

    // MARK: - Data signals

    var hasUncommittedChanges = false

    // MARK: - Chunk completed callbacks

    /// Registered observers for chunk completion events, keyed by UUID token.
    /// OutputStore calls `notifyChunkCompleted(_:)`, which fans out to all handlers.
    var chunkHandlers: [UUID: (OutputChunk) -> Void] = [:]

    // MARK: - Actions (called by AppCommands)

    func requestSearch() { showSearch = true }
    func requestNotes() { showNotes = true }
    func requestHarness() { showHarness = true }
    func requestBranchMerge() { showBranchMerge = true }

    func requestExport(sessionID: SessionID) {
        exportSessionID = sessionID
    }

    func prefillComposer(text: String) {
        pendingCommand = .composerPrefill(text: text)
    }

    func requestCloseTab() { pendingCommand = .closeTab }

    func toggleSessionInfo() {
        pendingCommand = .toggleSessionInfo
    }

    func toggleAgentDashboard() {
        pendingCommand = .toggleAgentDashboard
    }

    func toggleDualPane() {
        let prev = String(describing: pendingCommand)
        logger.info("[DIAG] toggleDualPane called, pendingCommand was \(prev)")
        pendingCommand = .toggleDualPane
    }

    func focusDualPane(_ slot: PaneSlot) {
        pendingCommand = .focusDualPane(slot)
    }
}
