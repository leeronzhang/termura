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

    @State var lastContentTabBySidebarTab: [SidebarTab: ContentTab] = [:]
    @State private var sidebarWidth: Double = AppConfig.UI.sidebarDefaultWidth
    @State var showDeleteSessionConfirm = false
    /// Explicitly managed terminal tab list (terminal + split entries).
    @State var terminalItems: [ContentTab] = []
    /// Which slot is focused within the current split tab.
    @State var focusedSlot: PaneSlot = .left
    /// Non-terminal tabs (files, notes, diffs).
    @State var openTabs: [ContentTab] = []
    @State var selectedContentTab: ContentTab?
    @State var isFullScreen = false
    /// The NSWindow hosting this view instance. Captured via HostingWindowCapture so that
    /// NotificationCenter observers can be filtered to this specific window only.
    @State private var hostingWindow: NSWindow?
    /// Tracks which pane slot the user is hovering over during a session drag, for drop-target highlighting.
    @State var dropTargetSlot: PaneSlot?

    // MARK: - Derived split-mode helpers (computed from selected tab)

    var leftPaneSessionID: SessionID? {
        guard let resolved = resolvedSelectedTab,
              case let .split(left, _, _, _) = resolved else { return nil }
        return left
    }

    var rightPaneSessionID: SessionID? {
        guard let resolved = resolvedSelectedTab,
              case let .split(_, right, _, _) = resolved else { return nil }
        return right
    }

    var isInSplitMode: Bool { resolvedSelectedTab?.isSplit ?? false }

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
        // Capture the hosting NSWindow so fullscreen observers are filtered per-window.
        // Required for correctness when multiple project windows are open simultaneously.
        .background(HostingWindowCapture { window in
            hostingWindow = window
            isFullScreen = window.styleMask.contains(.fullScreen)
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            guard (notification.object as? NSWindow) === hostingWindow else { return }
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            guard (notification.object as? NSWindow) === hostingWindow else { return }
            isFullScreen = false
        }
        // onChange inventory — limit: 5 (CLAUDE.md §5.5). Adding a 6th requires PR justification.
        // NOTE: .onChange attached anywhere in a MainView+*.swift @ViewBuilder also counts here.
        //   1. pendingCommand        — command channel (all menu/keyboard commands)
        //   2. focusedDualPaneID     — external sync (NSEvent monitor writes from outside SwiftUI)
        //   3. sessions.count        — external sync (actor state change, outside render cycle)
        //   4. selectedSidebarTab    — local state memory (needs old+new for tab history)
        //   5. selectedContentTab    — local state memory + dual-pane sync
        .onChange(of: commandRouter.pendingCommand) { _, command in
            guard let command else { return }
            commandRouter.pendingCommand = nil
            reduce(command: command)
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
        .onChange(of: commandRouter.selectedSidebarTab) { oldTab, newTab in
            restoreContentTabOnSidebarSwitch(from: oldTab, to: newTab)
        }
        .onChange(of: selectedContentTab) { _, newTab in
            if let newTab { trackContentTabForSidebarTab(newTab) }
            // Sync isDualPaneActive + focusedSlot when selected tab changes externally
            // (commands, session deletion, initial load) — not just user tab taps.
            guard let tab = newTab else { return }
            let isSplit = tab.isSplit
            commandRouter.isDualPaneActive = isSplit
            if isSplit {
                focusedSlot = .left
                commandRouter.focusedDualPaneID = leftPaneSessionID
            } else {
                commandRouter.focusedDualPaneID = nil
            }
        }
        .task {
            await ensureInitialSession()
            restoreOpenTabs()
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

    // MARK: - Sidebar panel

    @ViewBuilder
    private var sidebarPanel: some View {
        if commandRouter.showSidebar {
            SidebarView(
                isFullScreen: isFullScreen,
                activeContentTab: resolvedSelectedTab,
                selectedTab: router.selectedSidebarTab,
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
