import SwiftUI

// MARK: - Content display kind

/// Resolved display state for the content area.
/// Computed by `resolveContentDisplay(selectedTab:)` to avoid multi-dimensional
/// if/else chains directly inside `@ViewBuilder` bodies.
private enum ContentDisplay {
    /// No sessions exist or no matching terminal found — show the empty placeholder.
    case empty
    /// Notes tab is active but no note is selected — show the notes empty state.
    case notesEmpty
    /// Project tab is active but no file is open.
    case projectEmpty
    /// Harness tab is active but no rule file is open.
    case harnessEmpty
    /// Agents tab is active — content lives in the sidebar.
    case agentsEmpty
    /// Render the specified tab normally.
    case tab(ContentTab)
}

// MARK: - Content area views

extension MainView {
    // MARK: - Tab computation

    /// All tabs: explicit terminal items + non-terminal tabs (user-opened files/notes).
    var allTabs: [ContentTab] {
        terminalItems + openTabs
    }

    @ViewBuilder
    var contentArea: some View {
        VStack(spacing: 0) {
            ContentTabBar(
                tabs: allTabs,
                selectedTab: Binding(
                    get: { resolvedSelectedTab },
                    set: { newTab in
                        guard let newTab else { return }
                        tabManager.selectedContentTab = newTab
                        // Sync activeSessionID when switching tabs.
                        // Also sync selectedSidebarTab for non-terminal tabs so that
                        // selectedContentView shows the correct content instead of
                        // falling into the "Sessions tab + non-terminal = show terminal" branch.
                        switch newTab {
                        case let .terminal(sid, _):
                            sessionStore.activateSession(id: sid)
                        case let .split(left, right, _, _):
                            let sid = tabManager.focusedSlot == .left ? left : right
                            sessionStore.activateSession(id: sid)
                            commandRouter.isDualPaneActive = true
                        case .note:
                            commandRouter.selectedSidebarTab = .notes
                        case .diff, .file, .preview:
                            commandRouter.selectedSidebarTab = .project
                        }
                    }
                ),
                isFullScreen: isFullScreen,
                showSidebarButton: !commandRouter.showSidebar,
                onShowSidebar: {
                    withAnimation(.easeInOut(duration: AppUI.Animation.panel)) {
                        commandRouter.toggleSidebar()
                    }
                },
                onClose: { tab in closeContentTab(tab) },
                hasUncommittedChanges: commandRouter.hasUncommittedChanges,
                diagnosticErrorCount: projectScope.diagnosticsStore.errorCount
            )
            selectedContentView
        }
    }

    @ViewBuilder
    var selectedContentView: some View {
        if let tab = resolvedSelectedTab {
            switch resolveContentDisplay(selectedTab: tab) {
            case .empty: emptyState
            case .notesEmpty: notesEmptyState
            case .projectEmpty: projectEmptyState
            case .harnessEmpty: harnessEmptyState
            case .agentsEmpty: agentsEmptyState
            case let .tab(contentTab):
                tabContent(for: contentTab)
            }
        } else {
            emptyState
        }
    }

    /// Determines which display state the content area should render.
    ///
    /// Content tabs span freely across sidebar tabs — clicking any tab in the tab bar
    /// always shows that tab. Empty states are only shown when `restoreContentTabOnSidebarSwitch`
    /// failed to find content for the newly selected sidebar (tracked via `sidebarShowsEmpty`).
    private func resolveContentDisplay(selectedTab: ContentTab) -> ContentDisplay {
        let sidebar = commandRouter.selectedSidebarTab

        // Agents: always empty state (content lives in the sidebar dashboard).
        if sidebar == .agents { return .agentsEmpty }

        // Sessions: redirect non-terminal to the active terminal, or show empty.
        if sidebar == .sessions, !selectedTab.isTerminal, !selectedTab.isSplit {
            let best = sessionStore.activeSessionID.flatMap { activeID in
                terminalItems.first(where: { $0.containsSession(activeID) })
            } ?? terminalItems.first
            return best.map { .tab($0) } ?? .empty
        }

        // Composer notes mode: the overlay renders inside TerminalAreaView, so the
        // content area must show a terminal/split tab as the host.
        if sidebar == .notes, commandRouter.isComposerNotesActive,
           !selectedTab.isTerminal, !selectedTab.isSplit {
            let best = sessionStore.activeSessionID.flatMap { activeID in
                terminalItems.first(where: { $0.containsSession(activeID) })
            } ?? terminalItems.first
            return best.map { .tab($0) } ?? .tab(selectedTab)
        }

        // Sidebar switched but no content was restored — show the appropriate empty state.
        // This flag is set by restoreContentTabOnSidebarSwitch when no saved tab exists,
        // and cleared by onSelectedContentTabChange when the user explicitly selects a tab.
        if sidebarShowsEmpty.contains(sidebar) {
            return emptyDisplayFor(sidebar)
        }

        return .tab(selectedTab)
    }

    private func emptyDisplayFor(_ sidebar: SidebarTab) -> ContentDisplay {
        switch sidebar {
        case .sessions: .empty
        case .notes: .notesEmpty
        case .project: .projectEmpty
        case .harness: .harnessEmpty
        case .agents: .agentsEmpty
        }
    }

    @ViewBuilder
    private func tabContent(for tab: ContentTab) -> some View {
        switch tab {
        case let .terminal(sessionID, _):
            terminalView(for: sessionID)
                .id(sessionID)
        case .split:
            dualPaneView()
                .id(tab.id)
        case let .note(noteID, _):
            noteEditorView(noteID: noteID)
                .id(noteID)
        case let .diff(path, isStaged, isUntracked):
            DiffContentView(
                filePath: path,
                isStaged: isStaged,
                isUntracked: isUntracked,
                gitService: projectScope.gitService,
                projectRoot: activeProjectRoot
            )
            .id(tab.id)
        case let .file(path, _):
            CodeEditorView(
                filePath: path,
                projectRoot: activeProjectRoot
            )
            .id(path)
        case let .preview(path, _):
            FilePreviewView(
                filePath: path,
                projectRoot: activeProjectRoot
            )
            .id(path)
        }
    }

    /// Project root with fallback to active session working directory.
    var activeProjectRoot: String {
        if let root = sessionStore.projectRoot { return root }
        if let id = sessionStore.activeSessionID,
           let dir = sessionStore.session(id: id)?.workingDirectory {
            return dir
        }
        return AppConfig.Paths.homeDirectory
    }

    @ViewBuilder
    func terminalView(for sessionID: SessionID) -> some View {
        if let engine = engineStore.engine(for: sessionID) {
            let state = viewStateManager.viewState(for: sessionID, engine: engine)
            TerminalAreaView(
                engine: engine,
                sessionID: sessionID,
                state: state
            )
        } else {
            emptyState
        }
    }

    // Dual-pane view rendering is in MainView+DualPane.swift

    func noteEditorView(noteID: NoteID) -> some View {
        NoteTabContentView(
            noteID: noteID,
            notes: notes,
            onTitleChange: { id, title in syncNoteTabTitle(noteID: id, title: title) }
        )
    }

    private func syncNoteTabTitle(noteID: NoteID, title: String) {
        guard let idx = tabManager.openTabs.firstIndex(where: {
            if case let .note(id, _) = $0 { return id == noteID }
            return false
        }) else { return }
        tabManager.openTabs[idx] = .note(noteID: noteID, title: title)
        if case .note = tabManager.selectedContentTab { tabManager.selectedContentTab = tabManager.openTabs[idx] }
    }
}
