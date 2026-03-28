import SwiftUI

// MARK: - Pane slot

enum PaneSlot: Equatable {
    case left
    case right
}

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
    /// Explicitly managed terminal tab list (terminal + split entries).
    @State var terminalItems: [ContentTab] = []
    /// Which slot is focused within the current split tab.
    @State var focusedSlot: PaneSlot = .left
    /// Non-terminal tabs (files, notes, diffs).
    @State var openTabs: [ContentTab] = []
    @State var selectedContentTab: ContentTab?
    @State var isFullScreen = false

    // MARK: - Derived split-mode helpers (computed from selected tab)

    var leftPaneSessionID: SessionID? {
        guard case let .split(left, _, _, _) = resolvedSelectedTab else { return nil }
        return left
    }

    var rightPaneSessionID: SessionID? {
        guard case let .split(_, right, _, _) = resolvedSelectedTab else { return nil }
        return right
    }

    var isInSplitMode: Bool { resolvedSelectedTab.isSplit }

    var focusedPaneSessionID: SessionID? {
        focusedSlot == .left ? leftPaneSessionID : rightPaneSessionID
    }

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
            toggleSplitTab()
        }
        .onChange(of: commandRouter.focusedDualPaneID) { _, newID in
            guard let newID, isInSplitMode else { return }
            if newID == leftPaneSessionID {
                focusedSlot = .left
            } else if newID == rightPaneSessionID {
                focusedSlot = .right
            }
        }
        .onChange(of: sessionStore.sessions.count) { _, _ in
            syncTerminalItems()
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
                focusedSessionID: focusedPaneSessionID ?? sessionStore.activeSessionID,
                onActivateSession: { activateSessionFromSidebar($0) },
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
