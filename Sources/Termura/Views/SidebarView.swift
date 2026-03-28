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
    /// The currently visible content tab — used to suppress session highlight
    /// when a non-terminal tab (file, note, diff) is active.
    var activeContentTab: ContentTab?
    /// Session ID displayed in the dual-pane secondary (right) pane, if any.
    var splitSessionID: SessionID?
    /// Which pane is currently focused in dual-pane mode.
    var focusedPaneID: SessionID?
    /// Called when a session is tapped in dual-pane mode to set as secondary.
    var onSetSplitSession: ((SessionID) -> Void)?
    /// Called when a note title is tapped in the sidebar to open it as a content tab.
    var onOpenNote: ((NoteID, String) -> Void)?
    /// Called when a project file is tapped to open in a content tab.
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    // MARK: - Convenience

    var sessionStore: SessionStore { sessionScope.store }

    @State private var selectedTab: SidebarTab = .sessions
    /// Saved tab before composer auto-switched to .notes; restored on composer close.
    @State private var tabBeforeComposer: SidebarTab?
    /// Incremented to force re-render when agent states change (ObservableObject nested
    /// inside non-observable SessionScope breaks SwiftUI's automatic observation).
    @State var agentStateVersion: UInt = 0

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
        .onChange(of: commandRouter.isComposerNotesActive) { _, active in
            if active {
                if tabBeforeComposer == nil { tabBeforeComposer = selectedTab }
                withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                    selectedTab = .notes
                }
            } else if let previous = tabBeforeComposer {
                withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                    selectedTab = previous
                }
                tabBeforeComposer = nil
            }
        }
        .onChange(of: commandRouter.showComposer) { _, showing in
            guard !showing, let previous = tabBeforeComposer else { return }
            withAnimation(.easeInOut(duration: AppUI.Animation.quick)) {
                selectedTab = previous
            }
            tabBeforeComposer = nil
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
