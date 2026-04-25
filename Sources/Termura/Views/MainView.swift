import OSLog
import SwiftUI

// MARK: - Pane slot

enum PaneSlot: Hashable {
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
    @Environment(\.userDefaults) var userDefaults

    /// Bindable accessors for creating two-way bindings to @Observable environment objects.
    var router: Bindable<CommandRouter> { Bindable(commandRouter) }
    var notes: Bindable<NotesViewModel> { Bindable(notesViewModel) }

    @State var lastContentTabBySidebarTab: [SidebarTab: ContentTab] = [:]
    /// Sidebar tabs that should show their empty state because no content was restored
    /// on the last sidebar switch. Cleared when the user explicitly selects a content tab
    /// or when a restore succeeds.
    @State var sidebarShowsEmpty: Set<SidebarTab> = []
    @State private var sidebarWidth: Double = AppConfig.UI.sidebarDefaultWidth
    @State var showDeleteSessionConfirm = false
    @State var tabManager = TabManager()
    @State var isFullScreen = false
    /// The NSWindow hosting this view instance. Captured via HostingWindowCapture so that
    /// NotificationCenter observers can be filtered to this specific window only.
    @State private var hostingWindow: NSWindow?
    /// Tracks which pane slot the user is hovering over during a session drag, for drop-target highlighting.
    @State var dropTargetSlot: PaneSlot?

    // MARK: - Derived split-mode helpers (computed from selected tab)

    var leftPaneSessionID: SessionID? { tabManager.leftPaneSessionID }
    var rightPaneSessionID: SessionID? { tabManager.rightPaneSessionID }
    var isInSplitMode: Bool { tabManager.isInSplitMode }
    var focusedPaneSessionID: SessionID? { tabManager.focusedPaneSessionID }
    var resolvedSelectedTab: ContentTab? { tabManager.resolvedSelectedTab }
    var terminalItems: [ContentTab] { tabManager.terminalItems }
    var openTabs: [ContentTab] { tabManager.openTabs }
    var focusedSlot: PaneSlot { tabManager.focusedSlot }

    var selectedContentTab: ContentTab? {
        get { tabManager.selectedContentTab }
        set { tabManager.selectedContentTab = newValue }
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
        .modifier(FullScreenObservingModifier(isFullScreen: $isFullScreen, hostingWindow: $hostingWindow))
        // onChange × 5 — CLAUDE.md §5.5 cap. Adding a 6th requires PR justification.
        // 1.pendingCommand 2.focusedDualPaneID 3.sessions.count 4.selectedSidebarTab 5.selectedContentTab
        // NOTE: .onChange on any MainView+*.swift @ViewBuilder also counts toward this limit.
        .onChange(of: commandRouter.pendingCommand) { _, command in
            let log = Logger(subsystem: "com.termura.app", category: "MainView")
            log.info("[DIAG] onChange pendingCommand: \(String(describing: command))")
            guard let command else { return }
            commandRouter.pendingCommand = nil
            reduce(command: command)
        }
        .onChange(of: commandRouter.focusedDualPaneID) { _, newID in
            guard let newID, isInSplitMode else { return }
            tabManager.focusedSlot = newID == leftPaneSessionID ? .left : .right
        }
        .onChange(of: sessionStore.sessionTitles) { _, _ in syncTerminalItems() }
        .onChange(of: commandRouter.selectedSidebarTab) { oldTab, newTab in
            restoreContentTabOnSidebarSwitch(from: oldTab, to: newTab)
        }
        .onChange(of: selectedContentTab) { oldTab, newTab in onSelectedContentTabChange(old: oldTab, new: newTab) }
        .task {
            tabManager.inject(sessionStore: sessionStore, commandRouter: commandRouter)
            await ensureInitialSession()
            restoreOpenTabs()
            // Ensure selected tab matches the startup sidebar (.sessions).
            // restoreOpenTabs may have restored a file/note tab from the last session,
            // which would mismatch the sessions sidebar.
            ensureSelectedTabMatchesSidebar()
        }
        .sheet(isPresented: router.showSearch) { searchSheet }
        .sheet(isPresented: router.showNotes) { notesSheet }
        .sheet(isPresented: showExportBinding) { exportSheet }
        .sheet(isPresented: router.showHarness) { harnessSheet }
        .sheet(isPresented: router.showBranchMerge) { branchMergeSheet }
        .alert("Delete Session?", isPresented: $showDeleteSessionConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let sid = focusedPaneSessionID ?? sessionStore.activeSessionID
                if let sid { confirmDeleteSession(id: sid) }
            }
        } message: {
            Text("This session and all its history will be permanently removed.")
        }
    }

    // MARK: - onChange helpers

    private func onSelectedContentTabChange(old oldTab: ContentTab?, new newTab: ContentTab?) {
        // Clear the empty-state flag for the current sidebar so the tab is shown.
        sidebarShowsEmpty.remove(commandRouter.selectedSidebarTab)
        // Dismiss the Composer when the content tab actually changes.
        // Each EditorViewModel is bound to its own TerminalEngine; leaving the
        // Composer open across a tab switch would show the new tab's (empty) editor
        // while the user's in-progress text stays in the old tab's EditorViewModel —
        // pressing Enter would send a blank Return to the wrong session.
        if oldTab?.id != newTab?.id, commandRouter.showComposer {
            commandRouter.dismissComposer()
        }
        // Sync isDualPaneActive + focusedSlot when selected tab changes externally
        // (commands, session deletion, initial load) — not just user tab taps.
        guard let tab = newTab else { return }
        let isSplit = tab.isSplit
        let wasInDualPane = commandRouter.isDualPaneActive
        commandRouter.isDualPaneActive = isSplit
        if isSplit {
            // Reset focus when entering split mode OR switching to a different split tab.
            // Title-only refreshes (same tab.id, different title) must not steal pane focus —
            // otherwise any terminal output that changes the session title
            // (e.g. Codex running in the right pane) resets focus to .left.
            let isSameTab = oldTab?.id == tab.id
            if !wasInDualPane || !isSameTab {
                tabManager.focusedSlot = .left
                commandRouter.focusedDualPaneID = leftPaneSessionID
            }
        } else {
            commandRouter.focusedDualPaneID = nil
        }
    }

    // MARK: - Sidebar panel

    @ViewBuilder
    private var sidebarPanel: some View {
        if commandRouter.showSidebar {
            SidebarView(
                isFullScreen: isFullScreen,
                activeContentTab: resolvedSelectedTab,
                splitMemberships: tabManager.buildSplitMemberships(),
                selectedTab: router.selectedSidebarTab,
                focusedSessionID: focusedPaneSessionID ?? sessionStore.activeSessionID,
                onActivateSession: { activateSessionFromSidebar($0) },
                onOpenNote: { noteID, title in openNoteTab(noteID: noteID, title: title) },
                onOpenFile: { path, mode in openProjectFile(relativePath: path, mode: mode) }
            )
            .frame(width: sidebarWidth)
            .transition(.move(edge: .leading).combined(with: .opacity))

            ResizableDivider(
                width: $sidebarWidth,
                minWidth: AppConfig.UI.sidebarMinWidth,
                maxWidth: AppConfig.UI.sidebarMaxWidth,
                collapseThreshold: AppConfig.UI.sidebarCollapseThreshold,
                onCollapse: {
                    withAnimation(.easeInOut(duration: AppUI.Animation.panel)) {
                        sidebarWidth = AppConfig.UI.sidebarDefaultWidth
                        commandRouter.showSidebar = false
                    }
                }
            )
            .transition(.move(edge: .leading))
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

// MARK: - Hosting window capture

// MARK: - FullScreen observer modifier

/// Captures the hosting NSWindow and updates `isFullScreen` in response to enter/exit
/// fullscreen notifications, scoped to this specific window instance.
private struct FullScreenObservingModifier: ViewModifier {
    @Binding var isFullScreen: Bool
    @Binding var hostingWindow: NSWindow?
    private var notificationCenter: NotificationCenter? {
        GlobalEnvironmentDefaults.notificationCenter as? NotificationCenter
    }

    func body(content: Content) -> some View {
        let center = notificationCenter ?? .default
        let enterPublisher = center.publisher(for: NSWindow.didEnterFullScreenNotification)
        let exitPublisher = center.publisher(for: NSWindow.didExitFullScreenNotification)
        return content
            // Capture the hosting NSWindow so observers are filtered per-window.
            // Required for correctness when multiple project windows are open.
            .background(HostingWindowCapture { window in
                hostingWindow = window
                isFullScreen = window.styleMask.contains(.fullScreen)
            })
            .onReceive(enterPublisher) { n in
                guard (n.object as? NSWindow) === hostingWindow else { return }
                isFullScreen = true
            }
            .onReceive(exitPublisher) { n in
                guard (n.object as? NSWindow) === hostingWindow else { return }
                isFullScreen = false
            }
    }
}

// MARK: - Hosting window capture

/// Transparent NSViewRepresentable that resolves the hosting NSWindow via viewDidMoveToWindow.
/// This is the only reliable way to obtain the specific NSWindow for a SwiftUI view in a
/// multi-window app. The result is used to scope NotificationCenter observers to one window.
private struct HostingWindowCapture: NSViewRepresentable {
    let onWindowFound: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onWindowFound = onWindowFound
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {}

    final class CaptureView: NSView {
        var onWindowFound: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // viewDidMoveToWindow is called on the main thread. Invoking the callback
            // synchronously (rather than via Task { @MainActor }) ensures hostingWindow
            // is set in the same RunLoop cycle, so fullscreen notifications that fire
            // immediately cannot be silently dropped by the window-identity guard.
            MainActor.assumeIsolated { onWindowFound?(window) }
        }
    }
}
