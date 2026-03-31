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

    /// Resolved selected tab — nil when no tabs exist (e.g. during startup before sessions load).
    /// Callers must handle nil rather than receiving a ghost SessionID.
    var resolvedSelectedTab: ContentTab? {
        if let tab = selectedContentTab, allTabs.contains(tab) { return tab }
        return terminalItems.first ?? openTabs.first
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
                        selectedContentTab = newTab
                        // Sync activeSessionID when switching tabs.
                        // Also sync selectedSidebarTab for non-terminal tabs so that
                        // selectedContentView shows the correct content instead of
                        // falling into the "Sessions tab + non-terminal = show terminal" branch.
                        switch newTab {
                        case let .terminal(sid, _):
                            sessionStore.activateSession(id: sid)
                        case let .split(left, right, _, _):
                            let sid = focusedSlot == .left ? left : right
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
                onClose: { tab in closeContentTab(tab) }
            )
            selectedContentView
        }
    }

    @ViewBuilder
    var selectedContentView: some View {
        if let tab = resolvedSelectedTab {
            switch resolveContentDisplay(selectedTab: tab) {
            case .empty:
                emptyState
            case .notesEmpty:
                notesEmptyState
            case let .tab(contentTab):
                tabContent(for: contentTab)
            }
        } else {
            emptyState
        }
    }

    /// Determines which display state the content area should render.
    ///
    /// Encoding the three-way branch here keeps `selectedContentView` linear:
    /// - Sessions sidebar + non-terminal tab → redirect to the active terminal.
    /// - Notes sidebar + no note selected → show notes empty state.
    /// - Everything else → show the resolved tab normally.
    private func resolveContentDisplay(selectedTab: ContentTab) -> ContentDisplay {
        let sidebar = commandRouter.selectedSidebarTab

        // Sessions sidebar with a stale non-terminal tab selected (e.g. a note was
        // left open from the previous run): redirect to the active terminal, if any.
        if sidebar == .sessions, !selectedTab.isTerminal, !selectedTab.isSplit {
            let best = sessionStore.activeSessionID.flatMap { activeID in
                terminalItems.first(where: { $0.containsSession(activeID) })
            } ?? terminalItems.first
            return best.map { .tab($0) } ?? .empty
        }

        // Notes sidebar with no note tab selected and the Composer overlay not active:
        // the editor pane has nothing to show.
        if sidebar == .notes, !commandRouter.isComposerNotesActive, !selectedTab.isNote {
            return .notesEmpty
        }

        return .tab(selectedTab)
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
        guard let idx = openTabs.firstIndex(where: {
            if case let .note(id, _) = $0 { return id == noteID }
            return false
        }) else { return }
        openTabs[idx] = .note(noteID: noteID, title: title)
        if case .note = selectedContentTab { selectedContentTab = openTabs[idx] }
    }

}
