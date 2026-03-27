import SwiftUI

// MARK: - Content area views

extension MainView {
    // MARK: - Tab computation

    /// All tabs: one per session (derived) + non-terminal tabs (user-opened files/notes).
    var allTabs: [ContentTab] {
        let sessionTabs = sessionStore.sessions.map {
            ContentTab.terminal(sessionID: $0.id, title: $0.title)
        }
        return sessionTabs + openTabs
    }

    /// Resolved selected tab — falls back to the active session's terminal tab.
    var resolvedSelectedTab: ContentTab {
        if let tab = selectedContentTab, allTabs.contains(tab) { return tab }
        if let activeID = sessionStore.activeSessionID {
            let title = sessionStore.sessions.first { $0.id == activeID }?.title ?? "Terminal"
            return .terminal(sessionID: activeID, title: title)
        }
        return allTabs.first ?? .terminal(sessionID: SessionID(), title: "Terminal")
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
            selectedContentTab = .terminal(sessionID: newID, title: title)
        }
    }

    @ViewBuilder
    var selectedContentView: some View {
        switch resolvedSelectedTab {
        case let .terminal(sessionID, _):
            terminalView(for: sessionID)
                .id(sessionID)
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
            .id(resolvedSelectedTab.id)
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
           let session = sessionStore.sessions.first(where: { $0.id == id }),
           let dir = session.workingDirectory {
            return dir
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
        } else if let secondaryID = splitSessionID {
            dualPaneView(primaryID: sessionID, secondaryID: secondaryID)
        } else if let engine = engineStore.engine(for: sessionID) {
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

    @ViewBuilder
    private func dualPaneView(primaryID: SessionID, secondaryID: SessionID) -> some View {
        let focused = focusedPaneID ?? primaryID
        HStack(spacing: 0) {
            dualPaneTerminal(
                sessionID: primaryID, isFocused: focused == primaryID, hideButtons: true
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(width: 1)

            dualPaneTerminal(
                sessionID: secondaryID, isFocused: focused == secondaryID, hideButtons: false
            )

            dualPaneMetadata(focusedID: focused)
        }
        .onAppear {
            focusedPaneID = primaryID
            commandRouter.focusedDualPaneID = primaryID
        }
    }

    @ViewBuilder
    private func dualPaneTerminal(sessionID: SessionID, isFocused: Bool, hideButtons: Bool) -> some View {
        if let engine = engineStore.engine(for: sessionID) {
            let state = viewStateManager.viewState(for: sessionID, engine: engine)
            TerminalAreaView(
                engine: engine,
                sessionID: sessionID,
                forceHideMetadata: true,
                isFocusedPane: isFocused,
                hideToolbarButtons: hideButtons,
                state: state
            )
            .id(sessionID)
            .overlay(alignment: .top) {
                if isFocused {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedPaneID = sessionID
                        commandRouter.focusedDualPaneID = sessionID
                    }
            }
        }
    }

    @ViewBuilder
    private func dualPaneMetadata(focusedID: SessionID) -> some View {
        if let engine = engineStore.engine(for: focusedID) {
            let state = viewStateManager.viewState(for: focusedID, engine: engine)
            ResizableDivider(
                width: .constant(AppConfig.UI.metadataPanelWidth),
                minWidth: AppConfig.UI.metadataPanelMinWidth,
                maxWidth: AppConfig.UI.metadataPanelMaxWidth,
                dragFactor: -1.0
            )
            SessionMetadataBarView(
                metadata: state.viewModel.currentMetadata,
                timeline: state.timeline,
                onSelectChunkID: { _ in }
            )
            .frame(width: AppConfig.UI.metadataPanelWidth)
        }
    }

    func noteEditorView(noteID: NoteID) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppUI.Spacing.md) {
                TextField("Title", text: notes.editingTitle)
                    .font(AppUI.Font.title1Semibold)
                    .textFieldStyle(.plain)
                Spacer()
                noteFavoriteButton(noteID: noteID)
            }
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

    private func noteFavoriteButton(noteID: NoteID) -> some View {
        let isFav = notesViewModel.selectedNote?.isFavorite ?? false
        return Button {
            notesViewModel.toggleFavorite(id: noteID)
        } label: {
            Image(systemName: isFav ? "star.fill" : "star")
                .font(AppUI.Font.body)
                .foregroundColor(isFav ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .help(isFav ? "Remove from favorites" : "Add to favorites")
    }

    @ViewBuilder
    func renderLeaf(sessionID: SessionID) -> some View {
        if let engine = engineStore.engine(for: sessionID) {
            let state = viewStateManager.viewState(for: sessionID, engine: engine)
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
