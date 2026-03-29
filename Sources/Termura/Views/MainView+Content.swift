import SwiftUI

// MARK: - Content area views

extension MainView {
    // MARK: - Tab computation

    /// All tabs: explicit terminal items + non-terminal tabs (user-opened files/notes).
    var allTabs: [ContentTab] {
        terminalItems + openTabs
    }

    /// Resolved selected tab — falls back to the first terminal item.
    var resolvedSelectedTab: ContentTab {
        if let tab = selectedContentTab, allTabs.contains(tab) { return tab }
        return terminalItems.first ?? openTabs.first ?? .terminal(sessionID: SessionID(), title: "Terminal")
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
                isFullScreen: isFullScreen
            ) { tab in
                closeContentTab(tab)
            }
            selectedContentView
        }
        // Sync isDualPaneActive when selected tab changes.
        .onChange(of: selectedContentTab) { _, tab in
            guard let tab else { return }
            let isSplit = tab.isSplit
            commandRouter.isDualPaneActive = isSplit
            if isSplit {
                focusedSlot = .left
                commandRouter.focusedDualPaneID = leftPaneSessionID
            } else {
                commandRouter.focusedDualPaneID = nil
            }
        }
    }

    @ViewBuilder
    var selectedContentView: some View {
        let tab = resolvedSelectedTab
        // Sessions tab: if resolvedSelectedTab is not a terminal/split (e.g. a note or file tab
        // was left selected from a previous session), show the active terminal or empty state.
        if commandRouter.selectedSidebarTab == .sessions, !tab.isTerminal, !tab.isSplit {
            let best = terminalItems.first(where: {
                $0.containsSession(sessionStore.activeSessionID ?? SessionID())
            }) ?? terminalItems.first
            if let best {
                tabContent(for: best)
            } else {
                emptyState
            }
        // Notes tab: show the note editor if a note tab is selected, or an empty state otherwise.
        } else if commandRouter.selectedSidebarTab == .notes,
                  !commandRouter.isComposerNotesActive,
                  !tab.isNote {
            notesEmptyState
        } else {
            tabContent(for: tab)
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
    func dualPaneView() -> some View {
        HStack(spacing: 0) {
            dualPaneTerminal(sessionID: leftPaneSessionID, slot: .left, hideButtons: true)

            Rectangle()
                .fill(themeManager.current.sidebarText.opacity(AppUI.Opacity.softBorder))
                .frame(width: 1)

            dualPaneTerminal(sessionID: rightPaneSessionID, slot: .right, hideButtons: false)

            dualPaneMetadata(focusedID: focusedPaneSessionID)
        }
        .onAppear {
            focusedSlot = .left
            commandRouter.focusedDualPaneID = leftPaneSessionID
        }
    }

    @ViewBuilder
    func dualPaneTerminal(sessionID: SessionID?, slot: PaneSlot, hideButtons: Bool) -> some View {
        if let sessionID, let engine = engineStore.engine(for: sessionID) {
            let isFocused = focusedSlot == slot
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
                        focusedSlot = slot
                        commandRouter.focusedDualPaneID = sessionID
                        sessionStore.activateSession(id: sessionID)
                    }
            }
        }
    }

    @ViewBuilder
    private func dualPaneMetadata(focusedID: SessionID?) -> some View {
        if let focusedID,
           commandRouter.showDualPaneMetadata,
           let engine = engineStore.engine(for: focusedID) {
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
        .onChange(of: notesViewModel.editingTitle) { _, newTitle in
            syncNoteTabTitle(noteID: noteID, title: newTitle)
        }
    }

    private func syncNoteTabTitle(noteID: NoteID, title: String) {
        guard let idx = openTabs.firstIndex(where: {
            if case let .note(id, _) = $0 { return id == noteID }
            return false
        }) else { return }
        openTabs[idx] = .note(noteID: noteID, title: title)
        if case .note = selectedContentTab { selectedContentTab = openTabs[idx] }
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
