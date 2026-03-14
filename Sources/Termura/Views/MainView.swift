import SwiftUI

/// Root layout: horizontal split between sidebar and terminal area.
struct MainView: View {
    @ObservedObject var sessionStore: SessionStore
    let engineStore: TerminalEngineStore
    @ObservedObject var themeManager: ThemeManager
    let tokenCountingService: TokenCountingService
    let searchService: SearchService
    let noteRepository: any NoteRepositoryProtocol

    @State private var sidebarWidth: Double = AppConfig.UI.sidebarDefaultWidth
    @State private var showSidebar = true
    @State private var showShellOnboarding = false
    @State private var showSearch = false
    @State private var showNotes = false

    @StateObject private var notesViewModel: NotesViewModel

    init(
        sessionStore: SessionStore,
        engineStore: TerminalEngineStore,
        themeManager: ThemeManager,
        tokenCountingService: TokenCountingService,
        searchService: SearchService,
        noteRepository: any NoteRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.engineStore = engineStore
        self.themeManager = themeManager
        self.tokenCountingService = tokenCountingService
        self.searchService = searchService
        self.noteRepository = noteRepository
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
        .onAppear { ensureInitialSession() }
        .sheet(isPresented: $showShellOnboarding) {
            ShellIntegrationOnboardingView(isPresented: $showShellOnboarding)
        }
        .sheet(isPresented: $showSearch) {
            SearchView(
                searchService: searchService,
                isPresented: $showSearch,
                onSelectSession: { id in sessionStore.activateSession(id: id) }
            )
        }
        .sheet(isPresented: $showNotes) {
            NotesSplitView(viewModel: notesViewModel)
                .frame(minWidth: 600, minHeight: 400)
        }
    }

    // MARK: - Terminal area

    @ViewBuilder
    private var terminalArea: some View {
        if let activeID = sessionStore.activeSessionID,
           let engine = engineStore.engine(for: activeID) as? SwiftTermEngine {
            TerminalAreaView(
                engine: engine,
                sessionID: activeID,
                theme: themeManager.current,
                sessionStore: sessionStore,
                tokenCountingService: tokenCountingService
            )
            .id(activeID)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No Active Session")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(themeManager.current.foreground.opacity(0.5))
            Button("New Session") {
                sessionStore.createSession(title: "Terminal")
            }
            .keyboardShortcut("t", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.background)
    }

    // MARK: - Helpers

    private func ensureInitialSession() {
        if sessionStore.sessions.isEmpty {
            sessionStore.createSession(title: "Terminal")
        }
    }
}

extension Notification.Name {
    static let toggleSidebar = Notification.Name("com.termura.toggleSidebar")
    static let showShellIntegrationOnboarding = Notification.Name("com.termura.showShellOnboarding")
}
