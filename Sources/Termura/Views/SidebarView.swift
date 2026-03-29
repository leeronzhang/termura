import SwiftUI

/// Sidebar with Xcode-style tab bar: Sessions, Agents, Harness, Notes, Project.
struct SidebarView: View {
    @Environment(\.sessionScope) var sessionScope
    @Environment(\.dataScope) var dataScope
    @Environment(\.projectScope) var projectScope
    @Environment(\.themeManager) var themeManager
    @Environment(\.commandRouter) var commandRouter
    @Environment(\.notesViewModel) var notesViewModel

    var isFullScreen: Bool = false
    /// The currently selected content tab — used for session highlight logic.
    var activeContentTab: ContentTab?
    @Binding var selectedTab: SidebarTab
    /// The session that currently has keyboard focus (active in focused pane or single pane).
    var focusedSessionID: SessionID?
    /// Called when a session row is tapped — MainView handles find-tab-or-open logic.
    var onActivateSession: ((SessionRecord) -> Void)?
    /// Called when a note title is tapped in the sidebar to open it as a content tab.
    var onOpenNote: ((NoteID, String) -> Void)?
    /// Called when a project file is tapped to open in a content tab.
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    // MARK: - Convenience

    var sessionStore: SessionStore { sessionScope.store }

    var body: some View {
        VStack(spacing: 0) {
            SidebarTabBar(
                selectedTab: $selectedTab,
                isFullScreen: isFullScreen,
                hasUncommittedChanges: commandRouter.hasUncommittedChanges
            )
            tabContent
        }
        .frame(minWidth: AppConfig.UI.sidebarMinWidth, maxWidth: AppConfig.UI.sidebarMaxWidth)
        .background(.ultraThinMaterial)
        .onChange(of: commandRouter.toggleAgentDashboardTick) { _, _ in
            withAnimation(.easeInOut(duration: AppUI.Animation.panel)) {
                selectedTab = (selectedTab == .agents) ? .sessions : .agents
            }
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .sessions:
            sessionsContent
        case .agents:
            agentsContent
        case .project:
            projectContent
        case .notes:
            notesContent
        case .harness:
            harnessContent
        }
    }
}

/// How a file should be opened from the project sidebar.
enum FileOpenMode {
    case diff(staged: Bool, untracked: Bool)
    case edit
    case preview
}
