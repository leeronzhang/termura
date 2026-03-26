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
            sidebarPanel
            contentArea
        }
        .background(themeManager.current.background)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onChange(of: commandRouter.pendingSplitAction) { _, action in
            guard let action else { return }
            commandRouter.pendingSplitAction = nil
            switch action {
            case .vertical: performSplit(axis: .vertical)
            case .horizontal: performSplit(axis: .horizontal)
            case .closePane: performCloseSplitPane()
            }
        }
        .onChange(of: commandRouter.exportSessionID) { _, newID in
            guard newID != nil else { return }
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
        .sheet(isPresented: $commandRouter.showSearch) { searchSheet }
        .sheet(isPresented: $commandRouter.showNotes) { notesSheet }
        .sheet(isPresented: showExportBinding) { exportSheet }
        .sheet(isPresented: $commandRouter.showHarness) { harnessSheet }
        .sheet(isPresented: $commandRouter.showBranchMerge) { branchMergeSheet }
        .alert("Close Session", isPresented: $showCloseSessionConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Close", role: .destructive) { confirmCloseActiveSession() }
        } message: {
            Text("Are you sure you want to close the active session?")
        }
    }

    // MARK: - Sidebar panel

    @ViewBuilder
    private var sidebarPanel: some View {
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
