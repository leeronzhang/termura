import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "CommandRouter")

/// Type-safe command router replacing NotificationCenter for menu → view communication.
/// Owned per-project by `ProjectContext`; injected into the view hierarchy via `@EnvironmentObject`.
@MainActor
final class CommandRouter: ObservableObject {
    // MARK: - Sheet presentation

    @Published var showSearch = false
    @Published var showNotes = false
    @Published var showHarness = false
    @Published var showBranchMerge = false
    @Published var showShellOnboarding = false

    /// Non-nil triggers export sheet for the specified session.
    @Published var exportSessionID: SessionID?

    // MARK: - Sidebar

    @Published var showSidebar = true

    // MARK: - Split pane actions (consumed by MainView)

    @Published var pendingSplitAction: SplitAction?

    enum SplitAction: Equatable {
        case vertical, horizontal, closePane
    }

    // MARK: - Per-terminal toggles

    @Published var toggleTimelineTick: UInt = 0
    @Published var toggleAgentDashboardTick: UInt = 0

    // MARK: - Data signals

    @Published var hasUncommittedChanges = false

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
    @Published var closeTabTick: UInt = 0

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
}
