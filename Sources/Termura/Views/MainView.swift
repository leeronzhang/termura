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
    @State private var showExport = false
    @State private var exportSessionID: SessionID?
    @State private var showHarness = false
    @State private var showBranchMerge = false
    @State private var splitRoot: SplitNode?

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
                SidebarView(sessionStore: sessionStore)
                    .frame(width: sidebarWidth)
                    .environmentObject(themeManager)

                ResizableDivider(
                    width: $sidebarWidth,
                    minWidth: AppConfig.UI.sidebarMinWidth,
                    maxWidth: AppConfig.UI.sidebarMaxWidth
                )
            }

            terminalArea
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

    @ViewBuilder
    private var exportSheet: some View {
        // Export is handled by TerminalAreaView which has access to OutputStore chunks.
        // This sheet is a fallback for sessions without an active terminal.
        if let sid = exportSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == sid }) {
            ExportOptionsView(
                session: session,
                chunks: [],
                isPresented: $showExport
            )
        }
    }

    @ViewBuilder
    private var harnessSheet: some View {
        let appDel = NSApp.delegate as? AppDelegate
        if let repo = appDel?.ruleFileRepository {
            let projectRoot = activeSessionWorkingDirectory
            let vm = HarnessViewModel(repository: repo, projectRoot: projectRoot)
            HarnessSidebarView(viewModel: vm, isPresented: $showHarness)
                .frame(minWidth: 300, idealHeight: 500)
        } else {
            VStack(spacing: DS.Spacing.lg) {
                Text("Harness Rules")
                    .font(.headline)
                Text("Database not available.")
                    .foregroundColor(.secondary)
                Button("Close") { showHarness = false }
            }
            .frame(minWidth: 300, minHeight: 200)
            .padding(DS.Spacing.xxl)
        }
    }

    /// Working directory of the active session, falling back to home directory.
    private var activeSessionWorkingDirectory: String {
        if let activeID = sessionStore.activeSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == activeID }) {
            let dir = session.workingDirectory
            if !dir.isEmpty { return dir }
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    @ViewBuilder
    private var branchMergeSheet: some View {
        if let activeID = sessionStore.activeSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == activeID }),
           session.parentID != nil {
            BranchMergeSheet(
                branchSession: session,
                chunks: [],
                onMerge: { summary in
                    let msgRepo = (NSApp.delegate as? AppDelegate)?.sessionMessageRepository
                    Task {
                        await sessionStore.mergeBranchSummary(
                            branchID: activeID,
                            summary: summary,
                            messageRepo: msgRepo
                        )
                    }
                    showBranchMerge = false
                },
                onCancel: { showBranchMerge = false }
            )
        }
    }

    // MARK: - Terminal area

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
                contextInjectionService: contextInjectionService
            )
            .id(sessionID)
        } else {
            Text("No engine")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "terminal")
                .font(DS.Font.hero)
                .foregroundColor(themeManager.current.foreground.opacity(DS.Opacity.muted))
            Text("No Active Session")
                .font(DS.Font.title1)
                .foregroundColor(themeManager.current.foreground.opacity(DS.Opacity.dimmed))
            Text("Press \u{2318}T to create a new session")
                .font(DS.Font.label)
                .foregroundColor(themeManager.current.foreground.opacity(DS.Opacity.tertiary))
            Button("New Session") {
                sessionStore.createSession(title: "Terminal")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut("t", modifiers: .command)
            .padding(.top, DS.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.background)
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
