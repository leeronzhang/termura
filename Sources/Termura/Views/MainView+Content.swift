import SwiftUI

// MARK: - Content area views

extension MainView {
    // MARK: - Tab computation

    /// All tabs: one per session (derived) + non-terminal tabs (user-opened files/notes).
    var allTabs: [ContentTab] {
        let sessionTabs = sessionStore.sessions.map {
            ContentTab.terminal($0.id, $0.title)
        }
        return sessionTabs + openTabs
    }

    /// Resolved selected tab — falls back to the active session's terminal tab.
    var resolvedSelectedTab: ContentTab {
        if let tab = selectedContentTab, allTabs.contains(tab) { return tab }
        if let activeID = sessionStore.activeSessionID {
            let title = sessionStore.sessions.first { $0.id == activeID }?.title ?? "Terminal"
            return .terminal(activeID, title)
        }
        return allTabs.first ?? .terminal(SessionID(), "Terminal")
    }

    @ViewBuilder
    var contentArea: some View {
        VStack(spacing: 0) {
            ContentTabBar(
                tabs: allTabs,
                selectedTab: Binding(
                    get: { resolvedSelectedTab },
                    set: { newTab in
                        selectedContentTab = newTab
                        // Sync sidebar selection when a terminal tab is clicked.
                        if let sid = newTab.sessionID {
                            sessionStore.activateSession(id: sid)
                        }
                    }
                ),
                isFullScreen: isFullScreen
            ) { tab in
                closeContentTab(tab)
            }
            selectedContentView
        }
        .onReceive(sessionStore.$activeSessionID) { newID in
            // When sidebar selection changes, switch to that session's terminal tab.
            guard let newID else { return }
            let title = sessionStore.sessions.first { $0.id == newID }?.title ?? "Terminal"
            selectedContentTab = .terminal(newID, title)
        }
    }

    @ViewBuilder
    var selectedContentView: some View {
        switch resolvedSelectedTab {
        case .terminal(let sessionID, _):
            terminalView(for: sessionID)
                .id(sessionID)
        case .note(let noteID, _):
            noteEditorView(noteID: noteID)
                .id(noteID)
        case .diff(let path, let staged, let untracked):
            DiffContentView(
                filePath: path,
                isStaged: staged,
                isUntracked: untracked,
                gitService: projectContext.gitService,
                projectRoot: activeProjectRoot
            )
            .id(resolvedSelectedTab.id)
        case .file(let path, _):
            CodeEditorView(
                filePath: path,
                projectRoot: activeProjectRoot
            )
            .id(path)
        case .preview(let path, _):
            FilePreviewView(
                filePath: path,
                projectRoot: activeProjectRoot
            )
            .id(path)
        }
    }

    /// Project root with fallback to active session working directory.
    var activeProjectRoot: String {
        if !sessionStore.projectRoot.isEmpty { return sessionStore.projectRoot }
        if let id = sessionStore.activeSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == id }),
           !session.workingDirectory.isEmpty {
            return session.workingDirectory
        }
        return AppConfig.Paths.homeDirectory
    }

    @ViewBuilder
    func terminalView(for sessionID: SessionID) -> some View {
        if splitRoot != nil {
            SplitPaneView(
                node: Binding(
                    get: { splitRoot ?? .leaf(SessionID()) },
                    set: { splitRoot = $0 }
                ),
                renderLeaf: { id in AnyView(renderLeaf(sessionID: id)) }
            )
        } else if let engine = engineStore.engine(for: sessionID) {
            let state = projectContext.viewState(for: sessionID, engine: engine)
            TerminalAreaView(
                engine: engine,
                sessionID: sessionID,
                state: state
            )
        } else {
            emptyState
        }
    }

    func noteEditorView(noteID: NoteID) -> some View {
        VStack(spacing: 0) {
            TextField("Title", text: notes.editingTitle)
                .font(AppUI.Font.title1Semibold)
                .textFieldStyle(.plain)
                .padding(.horizontal, AppUI.Spacing.xl)
                .padding(.top, AppUI.Spacing.xl)
                .padding(.bottom, AppUI.Spacing.md)
            Divider()
            NoteEditorView(
                title: notesViewModel.editingTitle,
                text: notes.editingBody
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { notesViewModel.selectNote(id: noteID) }
    }

    @ViewBuilder
    func renderLeaf(sessionID: SessionID) -> some View {
        if let engine = engineStore.engine(for: sessionID) {
            let state = projectContext.viewState(for: sessionID, engine: engine)
            TerminalAreaView(
                engine: engine,
                sessionID: sessionID,
                isCompact: true,
                state: state
            )
            .id(sessionID)
        } else {
            Text("No engine")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
