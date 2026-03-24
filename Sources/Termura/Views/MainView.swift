import SwiftUI

/// Root layout: horizontal split between sidebar and terminal area.
struct MainView: View {
    @ObservedObject var sessionStore: SessionStore
    let engineStore: TerminalEngineStore
    @ObservedObject var themeManager: ThemeManager
    let tokenCountingService: TokenCountingService
    let searchService: SearchService
    let noteRepository: any NoteRepositoryProtocol
    var agentStateStore: AgentStateStore?
    var contextInjectionService: ContextInjectionService?

    @State private var sidebarWidth: Double = AppConfig.UI.sidebarDefaultWidth
    @State private var showSidebar = true
    @State private var showShellOnboarding = false
    @State private var showSearch = false
    @State private var showNotes = false
    @State var showExport = false
    @State var exportSessionID: SessionID?
    @State var showHarness = false
    @State var showBranchMerge = false
    @State private var splitRoot: SplitNode?
    @State var openTabs: [ContentTab] = [.terminal]
    @State var selectedContentTab: ContentTab = .terminal

    @StateObject private var notesViewModel: NotesViewModel

    init(
        sessionStore: SessionStore,
        engineStore: TerminalEngineStore,
        themeManager: ThemeManager,
        tokenCountingService: TokenCountingService,
        searchService: SearchService,
        noteRepository: any NoteRepositoryProtocol,
        agentStateStore: AgentStateStore? = nil,
        contextInjectionService: ContextInjectionService? = nil
    ) {
        self.sessionStore = sessionStore
        self.engineStore = engineStore
        self.themeManager = themeManager
        self.tokenCountingService = tokenCountingService
        self.searchService = searchService
        self.noteRepository = noteRepository
        self.agentStateStore = agentStateStore
        self.contextInjectionService = contextInjectionService
        _notesViewModel = StateObject(wrappedValue: NotesViewModel(repository: noteRepository))
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(
                    sessionStore: sessionStore,
                    agentStateStore: agentStateStore,
                    searchService: searchService,
                    noteRepository: noteRepository,
                    notesViewModel: notesViewModel,
                    onOpenNote: { noteID, title in openNoteTab(noteID: noteID, title: title) }
                )
                .frame(width: sidebarWidth)
                .environmentObject(themeManager)

                ResizableDivider(
                    width: $sidebarWidth,
                    minWidth: AppConfig.UI.sidebarMinWidth,
                    maxWidth: AppConfig.UI.sidebarMaxWidth
                )
            }

            contentArea
        }
        .background(themeManager.current.background)
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation { showSidebar.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showShellIntegrationOnboarding)) { _ in
            showShellOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSearch)) { _ in
            showSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNotes)) { _ in
            showNotes = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showExport)) { notification in
            exportSessionID = notification.object as? SessionID ?? sessionStore.activeSessionID
            showExport = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHarness)) { _ in
            showHarness = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showBranchMerge)) { _ in
            showBranchMerge = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .splitVertical)) { _ in
            performSplit(axis: .vertical)
        }
        .onReceive(NotificationCenter.default.publisher(for: .splitHorizontal)) { _ in
            performSplit(axis: .horizontal)
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeSplitPane)) { _ in
            performCloseSplitPane()
        }
        .task { await ensureInitialSession() }
        .sheet(isPresented: $showShellOnboarding) {
            ShellIntegrationOnboardingView(isPresented: $showShellOnboarding)
        }
        .sheet(isPresented: $showSearch) {
            SearchView(
                searchService: searchService,
                isPresented: $showSearch,
                onSelectSession: { id in sessionStore.activateSession(id: id) },
                vectorService: (NSApp.delegate as? AppDelegate)?.vectorSearchService
            )
        }
        .sheet(isPresented: $showNotes) {
            NotesSplitView(viewModel: notesViewModel)
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(isPresented: $showExport) {
            exportSheet
        }
        .sheet(isPresented: $showHarness) {
            harnessSheet
        }
        .sheet(isPresented: $showBranchMerge) {
            branchMergeSheet
        }
    }

    // MARK: - Content area with tabs

    @ViewBuilder
    private var contentArea: some View {
        VStack(spacing: 0) {
            if openTabs.count > 1 {
                ContentTabBar(tabs: openTabs, selectedTab: $selectedContentTab) { tab in
                    closeContentTab(tab)
                }
            }
            selectedContentView
        }
    }

    @ViewBuilder
    private var selectedContentView: some View {
        switch selectedContentTab {
        case .terminal:
            terminalArea
        case .note(let noteID, _):
            noteEditorView(noteID: noteID)
        }
    }

    @ViewBuilder
    private var terminalArea: some View {
        if splitRoot != nil {
            SplitPaneView(
                node: Binding(
                    get: { splitRoot ?? .leaf(SessionID()) },
                    set: { splitRoot = $0 }
                ),
                renderLeaf: { id in AnyView(renderLeaf(sessionID: id)) }
            )
        } else if let activeID = sessionStore.activeSessionID,
                  let engine = engineStore.engine(for: activeID) as? SwiftTermEngine {
            TerminalAreaView(
                engine: engine,
                sessionID: activeID,
                theme: themeManager.current,
                sessionStore: sessionStore,
                tokenCountingService: tokenCountingService,
                agentStateStore: agentStateStore,
                isRestoredSession: sessionStore.isRestoredSession(id: activeID),
                contextInjectionService: contextInjectionService
            )
            .id(activeID)
        } else {
            emptyState
        }
    }

    private func noteEditorView(noteID: NoteID) -> some View {
        VStack(spacing: 0) {
            TextField("Title", text: $notesViewModel.editingTitle)
                .font(.system(size: 16, weight: .semibold))
                .textFieldStyle(.plain)
                .padding(.horizontal, AppUI.Spacing.xl)
                .padding(.top, AppUI.Spacing.xl)
                .padding(.bottom, AppUI.Spacing.md)
            Divider()
            MarkdownEditorView(text: $notesViewModel.editingBody)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { notesViewModel.selectNote(id: noteID) }
    }

    @ViewBuilder
    private func renderLeaf(sessionID: SessionID) -> some View {
        if let engine = engineStore.engine(for: sessionID) as? SwiftTermEngine {
            TerminalAreaView(
                engine: engine,
                sessionID: sessionID,
                theme: themeManager.current,
                sessionStore: sessionStore,
                tokenCountingService: tokenCountingService,
                agentStateStore: agentStateStore,
                isRestoredSession: sessionStore.isRestoredSession(id: sessionID),
                contextInjectionService: contextInjectionService,
                isCompact: true
            )
            .id(sessionID)
        } else {
            Text("No engine")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Tab management

    func openNoteTab(noteID: NoteID, title: String) {
        let tab = ContentTab.note(noteID, title)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }

    private func closeContentTab(_ tab: ContentTab) {
        guard tab.isClosable else { return }
        openTabs.removeAll { $0 == tab }
        if selectedContentTab == tab {
            selectedContentTab = .terminal
        }
    }

    // MARK: - Helpers

    private func ensureInitialSession() async {
        // Wait for persisted sessions to be loaded before deciding
        // whether to create a fresh session.
        if !sessionStore.hasLoadedPersistedSessions {
            for await loaded in sessionStore.$hasLoadedPersistedSessions.values where loaded {
                break
            }
        }
        if sessionStore.sessions.isEmpty {
            sessionStore.createSession(title: "Terminal")
        }
    }

    private func performSplit(axis: SplitAxis) {
        guard let activeID = sessionStore.activeSessionID else { return }
        let newSession = sessionStore.createSession(title: "Terminal")
        if splitRoot == nil {
            splitRoot = SplitNodeMutations.splitLeaf(
                root: .leaf(activeID),
                targetID: activeID,
                newID: newSession.id,
                axis: axis
            )
        } else if let root = splitRoot {
            splitRoot = SplitNodeMutations.splitLeaf(
                root: root,
                targetID: activeID,
                newID: newSession.id,
                axis: axis
            )
        }
    }

    private func performCloseSplitPane() {
        guard let activeID = sessionStore.activeSessionID,
              let root = splitRoot else { return }
        if let remaining = SplitNodeMutations.removeLeaf(root: root, targetID: activeID) {
            if case .leaf = remaining {
                splitRoot = nil
            } else {
                splitRoot = remaining
            }
        } else {
            splitRoot = nil
        }
        sessionStore.closeSession(id: activeID)
    }
}

extension Notification.Name {
    static let toggleSidebar = Notification.Name("com.termura.toggleSidebar")
    static let showShellIntegrationOnboarding = Notification.Name("com.termura.showShellOnboarding")
}
