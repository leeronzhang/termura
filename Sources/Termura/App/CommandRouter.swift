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

    // MARK: - Per-terminal toggles

    var toggleTimelineTick: UInt = 0
    var toggleAgentDashboardTick: UInt = 0
    var showComposer: Bool = false

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

    func toggleComposer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showComposer.toggle()
        }
    }

    func dismissComposer() {
        withAnimation(.easeOut(duration: 0.2)) {
            showComposer = false
        }
    }
}
