import SwiftUI

/// Sidebar with Xcode-style tab bar: Sessions, Agents, Harness, Notes, Project.
struct SidebarView: View {
    @ObservedObject var sessionStore: SessionStore
    @EnvironmentObject var themeManager: ThemeManager
    var agentStateStore: AgentStateStore?
    var gitService: (any GitServiceProtocol)?
    var noteRepository: (any NoteRepositoryProtocol)?
    var notesViewModel: NotesViewModel?
    var ruleFileRepository: RuleFileRepository?
    var isFullScreen: Bool = false
    var hasUncommittedChanges: Bool = false
    /// Called when a note title is tapped in the sidebar to open it as a content tab.
    var onOpenNote: ((NoteID, String) -> Void)?
    /// Called when a project file is tapped to open in a content tab.
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    @State private var selectedTab: SidebarTab = .sessions

    var body: some View {
        VStack(spacing: 0) {
            SidebarTabBar(
                selectedTab: $selectedTab,
                isFullScreen: isFullScreen,
                hasUncommittedChanges: hasUncommittedChanges
            )
            tabContent
        }
        .frame(minWidth: AppConfig.UI.sidebarMinWidth, maxWidth: AppConfig.UI.sidebarMaxWidth)
        .background(.ultraThinMaterial)
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
}
