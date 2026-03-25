import SwiftUI

/// Sidebar with Xcode-style tab bar: Sessions, Agents, Search, Notes, Harness.
struct SidebarView: View {
    @ObservedObject var sessionStore: SessionStore
    @EnvironmentObject var themeManager: ThemeManager
    var agentStateStore: AgentStateStore?
    var searchService: SearchService?
    var noteRepository: (any NoteRepositoryProtocol)?
    var notesViewModel: NotesViewModel?
    var ruleFileRepository: RuleFileRepository?
    var isFullScreen: Bool = false
    /// Called when a note title is tapped in the sidebar to open it as a content tab.
    var onOpenNote: ((NoteID, String) -> Void)?

    @State private var selectedTab: SidebarTab = .sessions

    var body: some View {
        VStack(spacing: 0) {
            SidebarTabBar(selectedTab: $selectedTab, isFullScreen: isFullScreen)
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
        case .search:
            searchContent
        case .notes:
            notesContent
        case .harness:
            harnessContent
        }
    }
}
