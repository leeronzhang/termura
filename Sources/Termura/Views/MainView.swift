import SwiftUI

/// Root layout: horizontal split between sidebar and terminal area.
struct MainView: View {
    @Environment(\.sessionScope) var sessionScope
    @Environment(\.dataScope) var dataScope
    @Environment(\.projectScope) var projectScope
    @Environment(\.viewStateManager) var viewStateManager
    @Environment(\.themeManager) var themeManager
    @Environment(\.commandRouter) var commandRouter
    @Environment(\.notesViewModel) var notesViewModel

    /// Bindable accessors for creating two-way bindings to @Observable environment objects.
    var router: Bindable<CommandRouter> { Bindable(commandRouter) }
    var notes: Bindable<NotesViewModel> { Bindable(notesViewModel) }

    @State private var sidebarWidth: Double = AppConfig.UI.sidebarDefaultWidth
    @State var showCloseSessionConfirm = false
    @State var splitRoot: SplitNode?
    /// Session ID shown in the right pane of dual-pane mode. Nil = single pane.
    @State var splitSessionID: SessionID?
    /// Which pane is focused/active in dual-pane mode (for metadata display + sidebar highlight).
    @State var focusedPaneID: SessionID?
    /// Non-terminal tabs (files, notes, diffs). Terminal tabs are derived from sessions.
    @State var openTabs: [ContentTab] = []
    @State var selectedContentTab: ContentTab?
    @State var isFullScreen = false

    // MARK: - Convenience accessors

    var sessionStore: SessionStore { sessionScope.store }
    var engineStore: TerminalEngineStore { sessionScope.engines }

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
        .onChange(of: commandRouter.dualPaneToggleTick) { _, _ in
            toggleDualPane()
        }
        .onChange(of: commandRouter.focusedDualPaneID) { _, newID in
            guard let newID, splitSessionID != nil else { return }
            focusedPaneID = newID
        }
        .onChange(of: sessionStore.sessions.count) { _, _ in
            // Clear split if the secondary session was closed.
            if let splitID = splitSessionID,
               !sessionStore.sessions.contains(where: { $0.id == splitID }) {
                splitSessionID = nil
                commandRouter.isDualPaneActive = false
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
        .sheet(isPresented: router.showShellOnboarding) {
            ShellIntegrationOnboardingView(isPresented: router.showShellOnboarding)
        }
        .sheet(isPresented: router.showSearch) { searchSheet }
        .sheet(isPresented: router.showNotes) { notesSheet }
        .sheet(isPresented: showExportBinding) { exportSheet }
        .sheet(isPresented: router.showHarness) { harnessSheet }
        .sheet(isPresented: router.showBranchMerge) { branchMergeSheet }
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
                splitSessionID: splitSessionID,
                focusedPaneID: focusedPaneID,
                onSetSplitSession: { setDualPaneSecondary(id: $0) },
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
