import SwiftUI

/// Root layout: horizontal split between sidebar and terminal area.
struct MainView: View {
    @EnvironmentObject var projectContext: ProjectContext
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var commandRouter: CommandRouter
    @EnvironmentObject var notesViewModel: NotesViewModel

    @State private var sidebarWidth: Double = AppConfig.UI.sidebarDefaultWidth
    @State var showCloseSessionConfirm = false
    @State var splitRoot: SplitNode?
    /// Non-terminal tabs (files, notes, diffs). Terminal tabs are derived from sessions.
    @State var openTabs: [ContentTab] = []
    @State var selectedContentTab: ContentTab?
    @State var isFullScreen = false

    // MARK: - Convenience accessors

    var sessionStore: SessionStore { projectContext.sessionStore }
    var engineStore: TerminalEngineStore { projectContext.engineStore }

    var body: some View {
        HStack(spacing: 0) {
            if commandRouter.showSidebar {
                SidebarView(
                    isFullScreen: isFullScreen,
                    activeContentTab: resolvedSelectedTab,
                    onOpenNote: { noteID, title in openNoteTab(noteID: noteID, title: title) },
                    onOpenFile: { path, mode in openProjectFile(relativePath: path, mode: mode) }
                )
                .frame(width: sidebarWidth)

                ResizableDivider(
                    width: $sidebarWidth,
                    minWidth: AppConfig.UI.sidebarMinWidth,
                    maxWidth: AppConfig.UI.sidebarMaxWidth
                )
            }

            contentArea
        }
        .background(themeManager.current.background)
        // System-level notifications — Apple convention, kept as-is.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        // React to CommandRouter split actions.
        .onChange(of: commandRouter.pendingSplitAction) { _, action in
            guard let action else { return }
            commandRouter.pendingSplitAction = nil
            switch action {
            case .vertical: performSplit(axis: .vertical)
            case .horizontal: performSplit(axis: .horizontal)
            case .closePane: performCloseSplitPane()
            }
        }
        // React to export requests with session ID payload.
        .onChange(of: commandRouter.exportSessionID) { _, newID in
            guard newID != nil else { return }
            // exportSessionID stays non-nil while sheet is shown;
            // sheet binding resets it on dismiss.
        }
        .onChange(of: commandRouter.closeTabTick) { _, _ in
            handleCloseTab()
        }
        .task {
            await ensureInitialSession()
            restoreOpenTabs()
        }
        .sheet(isPresented: $commandRouter.showShellOnboarding) {
            ShellIntegrationOnboardingView(isPresented: $commandRouter.showShellOnboarding)
        }
        .sheet(isPresented: $commandRouter.showSearch) {
            SearchView(
                searchService: projectContext.searchService,
                isPresented: $commandRouter.showSearch,
                onSelectSession: { id in sessionStore.activateSession(id: id) },
                vectorService: projectContext.vectorSearchService
            )
        }
        .sheet(isPresented: $commandRouter.showNotes) {
            NotesSplitView(viewModel: notesViewModel)
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(isPresented: showExportBinding) {
            exportSheet
        }
        .sheet(isPresented: $commandRouter.showHarness) {
            harnessSheet
        }
        .sheet(isPresented: $commandRouter.showBranchMerge) {
            branchMergeSheet
        }
        .alert("Close Session", isPresented: $showCloseSessionConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Close", role: .destructive) { confirmCloseActiveSession() }
        } message: {
            Text("Are you sure you want to close the active session?")
        }
    }

    // MARK: - Export binding

    /// Derived binding: export sheet is shown when `exportSessionID` is non-nil.
    private var showExportBinding: Binding<Bool> {
        Binding(
            get: { commandRouter.exportSessionID != nil },
            set: { if !$0 { commandRouter.exportSessionID = nil } }
        )
    }
}
