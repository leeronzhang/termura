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
    @State var showCloseSessionConfirm = false
    @State var splitRoot: SplitNode?
    @State var openTabs: [ContentTab] = [.terminal]
    @State var selectedContentTab: ContentTab = .terminal
    @State private var isFullScreen = false

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
                    isFullScreen: isFullScreen,
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
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
        .alert("Close Session", isPresented: $showCloseSessionConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Close", role: .destructive) { confirmCloseActiveSession() }
        } message: {
            Text("Are you sure you want to close the active session?")
        }
    }

    // MARK: - Content area with tabs

    @ViewBuilder
    private var contentArea: some View {
        VStack(spacing: 0) {
            ContentTabBar(
                tabs: openTabs,
                selectedTab: $selectedContentTab,
                isFullScreen: isFullScreen
            ) { tab in
                closeContentTab(tab)
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

}
