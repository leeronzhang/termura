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
    private var tabBeforeComposer: SidebarTab?

    // MARK: - Commands (consumed by MainView via a single reduce step)

    /// Pending command for MainView to process. Cleared by MainView after handling.
    /// All command-driven side-effects funnel through here to avoid concurrent .onChange races.
    var pendingCommand: PendingCommand?

    enum PendingCommand: Equatable {
        case split(SplitAction)
        case toggleDualPane
        case closeTab
        case createNote
        case toggleTimeline
        case toggleAgentDashboard
        /// Pre-fills the Composer with the agent's default launch command and opens it.
        /// Fired once per restored session when the first shell prompt is detected.
        case resumeAgent(AgentType)
        /// Pre-fills the Composer with a quoted selection from the terminal output.
        /// Opens the Composer if not already visible, or appends if it is.
        case composerPrefill(text: String)
    }

    enum SplitAction: Equatable {
        case vertical, horizontal, closePane
    }

    // MARK: - Dual pane

    /// Whether dual-pane (side-by-side) mode is active. Toolbar reads this for visual state.
    var isDualPaneActive = false
    /// Tracks which pane was last clicked in dual-pane mode (set by NSEvent monitors).
    var focusedDualPaneID: SessionID?
    /// Whether the session-info metadata panel is visible in dual-pane mode.
    /// Toggled by the info toolbar button; applies globally (not per-pane).
    var showDualPaneMetadata = true

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
    private var chunkHandlers: [UUID: (OutputChunk) -> Void] = [:]

    /// Register a handler to be called when any OutputStore appends a chunk.
    /// Returns a token that MUST be stored and passed to `removeChunkHandler(token:)` on teardown.
    func onChunkCompleted(_ handler: @escaping (OutputChunk) -> Void) -> UUID {
        let token = UUID()
        chunkHandlers[token] = handler
        return token
    }

    /// Unregister a previously registered handler. Safe to call with an unknown token.
    func removeChunkHandler(token: UUID) {
        chunkHandlers.removeValue(forKey: token)
    }

    /// Called by OutputStore when a chunk is appended.
    func notifyChunkCompleted(_ chunk: OutputChunk) {
        for handler in chunkHandlers.values {
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

    func prefillComposer(text: String) {
        pendingCommand = .composerPrefill(text: text)
    }

    func requestCloseTab() { pendingCommand = .closeTab }
    func requestSplitHorizontal() { pendingCommand = .split(.horizontal) }
    func requestSplitVertical() { pendingCommand = .split(.vertical) }
    func requestCloseSplitPane() { pendingCommand = .split(.closePane) }

    func toggleSidebar() {
        showSidebar.toggle()
    }

    func toggleTimeline() {
        pendingCommand = .toggleTimeline
    }

    func toggleAgentDashboard() {
        pendingCommand = .toggleAgentDashboard
    }

    func toggleDualPane() {
        pendingCommand = .toggleDualPane
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
        if let previous = tabBeforeComposer {
            selectedSidebarTab = previous
            tabBeforeComposer = nil
        }
        isComposerNotesActive = false
        withAnimation(.easeOut(duration: AppConfig.UI.composerDismissDuration)) {
            showComposer = false
        }
    }

    /// Toggles the sidebar Notes tab from the Composer notes button.
    /// Both isComposerNotesActive and selectedSidebarTab change in the same call so
    /// SwiftUI batches them into one render pass — no intermediate notesEmptyState flash.
    func toggleComposerNotes() {
        if !isComposerNotesActive {
            isComposerNotesActive = true
            tabBeforeComposer = selectedSidebarTab
            withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                selectedSidebarTab = .notes
            }
        } else if let previous = tabBeforeComposer {
            // Close: both state changes inside one animation block so SwiftUI
            // produces a single render pass — prevents notesEmptyState flashing
            // when selectedSidebarTab is still .notes but isComposerNotesActive
            // has already flipped to false.
            tabBeforeComposer = nil
            withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                isComposerNotesActive = false
                selectedSidebarTab = previous
            }
        }
    }
}
