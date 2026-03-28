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
    var showShellOnboarding = false

    /// Non-nil triggers export sheet for the specified session.
    var exportSessionID: SessionID?

    // MARK: - Sidebar

    var showSidebar = true

    // MARK: - Split pane actions (consumed by MainView)

    var pendingSplitAction: SplitAction?

    enum SplitAction: Equatable {
        case vertical, horizontal, closePane
    }

    // MARK: - Dual pane

    /// Whether dual-pane (side-by-side) mode is active. Toolbar reads this for visual state.
    var isDualPaneActive = false
    var dualPaneToggleTick: UInt = 0
    /// Tracks which pane was last clicked in dual-pane mode (set by NSEvent monitors).
    var focusedDualPaneID: SessionID?
    /// Whether the session-info metadata panel is visible in dual-pane mode.
    /// Toggled by the info toolbar button; applies globally (not per-pane).
    var showDualPaneMetadata = true

    // MARK: - Per-terminal toggles

    var toggleTimelineTick: UInt = 0
    var toggleAgentDashboardTick: UInt = 0
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

    /// Registered observers for chunk completion events.
    /// OutputStore calls `notifyChunkCompleted(_:)`, which fans out to all handlers.
    private var chunkHandlers: [(OutputChunk) -> Void] = []

    /// Register a handler to be called when any OutputStore appends a chunk.
    /// Returns a token that can be used to unregister.
    @discardableResult
    func onChunkCompleted(_ handler: @escaping (OutputChunk) -> Void) -> Int {
        let token = chunkHandlers.count
        chunkHandlers.append(handler)
        return token
    }

    /// Called by OutputStore when a chunk is appended.
    func notifyChunkCompleted(_ chunk: OutputChunk) {
        for handler in chunkHandlers {
            handler(chunk)
        }
    }

    // MARK: - Actions (called by AppCommands)

    func requestSearch() { showSearch = true }
    func requestNotes() { showNotes = true }
    func requestHarness() { showHarness = true }
    func requestBranchMerge() { showBranchMerge = true }

    func requestExport(sessionID: SessionID) {
        exportSessionID = sessionID
    }

    /// Incremented when user presses Cmd+W — MainView observes and closes the active tab.
    var closeTabTick: UInt = 0

    func requestCloseTab() { closeTabTick &+= 1 }
    func requestSplitHorizontal() { pendingSplitAction = .horizontal }
    func requestSplitVertical() { pendingSplitAction = .vertical }
    func requestCloseSplitPane() { pendingSplitAction = .closePane }

    func toggleSidebar() {
        showSidebar.toggle()
    }

    func toggleTimeline() {
        toggleTimelineTick &+= 1
    }

    func toggleAgentDashboard() {
        toggleAgentDashboardTick &+= 1
    }

    func toggleDualPane() {
        dualPaneToggleTick &+= 1
    }

    func toggleComposer() {
        withAnimation(.spring(
            response: AppConfig.UI.composerSpringResponse,
            dampingFraction: AppConfig.UI.composerSpringDamping
        )) {
            showComposer.toggle()
        }
    }

    func dismissComposer() {
        composerInsertHandler = nil
        isComposerNotesActive = false
        withAnimation(.easeOut(duration: AppConfig.UI.composerDismissDuration)) {
            showComposer = false
        }
    }

    /// Toggles the sidebar Notes tab from the Composer notes button.
    /// SidebarView reacts via `.onChange(of: commandRouter.isComposerNotesActive)`.
    func toggleComposerNotes() {
        isComposerNotesActive.toggle()
    }
}
