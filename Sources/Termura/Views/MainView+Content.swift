import SwiftUI

// MARK: - Content area views

extension MainView {
    static let markdownExtensions: Set<String> = ["md", "markdown"]

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
                    get: {
                        if sidebarShowsEmpty.contains(commandRouter.selectedSidebarTab) {
                            return nil
                        }
                        return resolvedSelectedTab
                    },
                    set: { newTab in
                        guard let newTab else { return }
                        tabManager.selectedContentTab = newTab
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

    /// Content area renders whatever `selectedContentTab` points to.
    /// No display-only overrides — `selectedContentTab` is the single source of truth.
    /// `restoreContentTabOnSidebarSwitch` is responsible for setting it correctly.
    @ViewBuilder
    var selectedContentView: some View {
        let sidebar = commandRouter.selectedSidebarTab

        if sidebar == .agents {
            agentsEmptyState
        } else if sidebarShowsEmpty.contains(sidebar) {
            emptyStateFor(sidebar)
        } else if let tab = resolvedSelectedTab {
            tabContent(for: tab)
        } else {
            emptyStateFor(sidebar)
        }
    }

    @ViewBuilder
    private func emptyStateFor(_ sidebar: SidebarTab) -> some View {
        switch sidebar {
        case .sessions: emptyState
        case .notes: notesEmptyState
        case .project: projectEmptyState
        case .harness: harnessEmptyState
        case .agents: agentsEmptyState
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
            if Self.markdownExtensions.contains(
                URL(fileURLWithPath: path).pathExtension.lowercased()
            ) {
                MarkdownFileView(filePath: path, projectRoot: activeProjectRoot)
                    .id(path)
            } else {
                CodeEditorView(filePath: path, projectRoot: activeProjectRoot)
                    .id(path)
            }
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
            // Engine not yet created — loadPersistedSessions only pre-creates the
            // engine for the most-recently-active session; all others are created on
            // demand when their tab becomes visible (tab switch, startup restore, etc.).
            // TerminalEngineStore is @Observable, so the view re-renders once the
            // engine is inserted.
            Color.clear
                .task(id: sessionID) {
                    sessionStore.ensureEngine(for: sessionID, shell: nil)
                }
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
