import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "MainView+Actions")

// MARK: - Command reducer

extension MainView {
    /// Single entry point for all command-driven UI mutations.
    /// Called from the unified `.onChange(of: commandRouter.pendingCommand)` in MainView.body.
    func reduce(command: CommandRouter.PendingCommand) {
        switch command {
        case .split(let action):
            switch action {
            case .vertical: performSplit(axis: .vertical)
            case .horizontal: performSplit(axis: .horizontal)
            case .closePane: performCloseSplitPane()
            }
        case .toggleDualPane:
            toggleSplitTab()
        case .closeTab:
            handleCloseTab()
        case .createNote:
            handleCreateNote()
        case .toggleTimeline:
            handleToggleTimeline()
        case .toggleAgentDashboard:
            handleToggleAgentDashboard()
        case .resumeAgent(let agentType):
            handleAgentResume(agentType)
        case .composerPrefill(let text):
            handleComposerPrefill(text)
        }
    }

    /// Returns the EditorViewModel for the currently focused session, if available.
    private var activeEditorViewModel: EditorViewModel? {
        let sid = focusedPaneSessionID ?? sessionStore.activeSessionID
        guard let sid else { return nil }
        return viewStateManager.sessionViewStates[sid]?.editorViewModel
    }

    /// Pre-fills the Composer with quoted terminal output and opens it (or appends if already open).
    private func handleComposerPrefill(_ text: String) {
        guard let editorVM = activeEditorViewModel else { return }
        if commandRouter.showComposer {
            editorVM.appendText(text)
        } else {
            editorVM.setText(text)
            commandRouter.toggleComposer()
        }
    }

    /// Toggles the session-info metadata panel for the focused session.
    /// In dual-pane mode the toggle is global (CommandRouter.showDualPaneMetadata);
    /// in single-pane mode it is per-session (SessionViewState.showMetadata).
    private func handleToggleTimeline() {
        if commandRouter.isDualPaneActive {
            withAnimation { commandRouter.showDualPaneMetadata.toggle() }
        } else {
            let sid = focusedPaneSessionID ?? sessionStore.activeSessionID
            guard let sid else { return }
            guard let viewState = viewStateManager.sessionViewStates[sid] else { return }
            withAnimation { viewState.showMetadata.toggle() }
        }
    }

    /// Toggles the sidebar between the Agents tab and the previously selected tab.
    private func handleToggleAgentDashboard() {
        withAnimation(.easeInOut(duration: AppUI.Animation.panel)) {
            commandRouter.selectedSidebarTab = (commandRouter.selectedSidebarTab == .agents) ? .sessions : .agents
        }
    }

    /// Pre-fills the Composer with the agent's default launch command and opens it.
    /// No-ops if the feature is disabled, the Composer is already open, or the editor
    /// already contains text (user may have typed something before the prompt fired).
    private func handleAgentResume(_ agentType: AgentType) {
        let key = AppConfig.AgentResume.autoFillEnabledKey
        let enabled = UserDefaults.standard.object(forKey: key) as? Bool
                      ?? AppConfig.AgentResume.autoFillDefault
        guard enabled else { return }
        guard !commandRouter.showComposer else { return }
        guard let editorVM = activeEditorViewModel else { return }
        guard editorVM.currentText.isEmpty else { return }
        let command = agentType.defaultLaunchCommand
        guard !command.isEmpty else { return }
        editorVM.setText(command)
        commandRouter.toggleComposer()
    }
}

// MARK: - Tab management

extension MainView {
    func openNoteTab(noteID: NoteID, title: String) {
        let tab = ContentTab.note(noteID: noteID, title: title)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
        persistOpenTabs()
    }

    func openDiffTab(path: String, staged: Bool, untracked: Bool = false) {
        let tab = ContentTab.diff(path: path, isStaged: staged, isUntracked: untracked)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }

    func openFileTab(path: String, name: String) {
        let tab = ContentTab.file(path: path, name: name)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
        persistOpenTabs()
    }

    func openPreviewTab(path: String, name: String) {
        let tab = ContentTab.preview(path: path, name: name)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
        persistOpenTabs()
    }

    func openProjectFile(relativePath: String, mode: FileOpenMode) {
        let name = URL(fileURLWithPath: relativePath).lastPathComponent
        switch mode {
        case let .diff(staged, untracked):
            openDiffTab(path: relativePath, staged: staged, untracked: untracked)
        case .edit:
            openFileTab(path: relativePath, name: name)
        case .preview:
            openPreviewTab(path: relativePath, name: name)
        }
    }

    func closeContentTab(_ tab: ContentTab) {
        switch tab {
        case .terminal, .split:
            // Managed via sidebar / session lifecycle, not closable from tab bar.
            break
        case .note, .diff, .file, .preview:
            openTabs.removeAll { $0 == tab }
            if selectedContentTab == tab {
                selectedContentTab = nil
            }
            persistOpenTabs()
        }
    }

    /// Cmd+W handler: close focused session if on a terminal/split tab, or close a non-terminal tab.
    func handleCloseTab() {
        let tab = resolvedSelectedTab
        if tab.isClosable {
            closeContentTab(tab)
        } else if tab.isTerminal || tab.isSplit {
            showCloseSessionConfirm = true
        }
    }

    func handleCreateNote() {
        commandRouter.selectedSidebarTab = .notes
        notesViewModel.createNote()
        if let noteID = notesViewModel.selectedNoteID,
           let note = notesViewModel.selectedNote {
            openNoteTab(noteID: noteID, title: note.title)
        }
    }

    func confirmCloseActiveSession() {
        let sessionID = focusedPaneSessionID ?? sessionStore.activeSessionID
        guard let sid = sessionID else { return }
        Task { @MainActor in
            await sessionStore.closeSession(id: sid)
            // Only update tab state if the session was actually removed from the store.
            // closeSession returns without mutating sessions if the DB delete failed.
            guard !sessionStore.sessions.contains(where: { $0.id == sid }) else { return }
            // Dissolve or remove the tab that contained the closed session.
            if let idx = terminalItems.firstIndex(where: { $0.containsSession(sid) }) {
                let item = terminalItems[idx]
                if case let .split(left, right, leftTitle, rightTitle) = item {
                    let survivingID = left == sid ? right : left
                    let survivingTitle = left == sid ? rightTitle : leftTitle
                    let replacement = ContentTab.terminal(sessionID: survivingID, title: survivingTitle)
                    terminalItems[idx] = replacement
                    selectedContentTab = replacement
                    sessionStore.activateSession(id: survivingID)
                } else {
                    terminalItems.remove(at: idx)
                    selectedContentTab = terminalItems.last ?? openTabs.first
                    if let next = selectedContentTab?.sessionID {
                        sessionStore.activateSession(id: next)
                    }
                }
            }
        }
    }
}

// MARK: - Session activation (from sidebar)

extension MainView {
    /// Called when the user taps a session in the sidebar.
    /// Jumps to the existing tab containing the session, or opens a new terminal tab.
    func activateSessionFromSidebar(_ session: SessionRecord) {
        if let tab = terminalItems.first(where: { $0.containsSession(session.id) }) {
            selectedContentTab = tab
            if case let .split(left, _, _, _) = tab {
                focusedSlot = session.id == left ? .left : .right
            }
        } else {
            let tab = ContentTab.terminal(sessionID: session.id, title: session.title)
            terminalItems.append(tab)
            selectedContentTab = tab
        }
        sessionStore.activateSession(id: session.id)
    }
}

// MARK: - Split tab management

extension MainView {
    /// Toggles the current terminal tab between single and split (two-pane) mode.
    func toggleSplitTab() {
        let current = resolvedSelectedTab
        if current.isSplit {
            dissolveSplitTab()
        } else if case let .terminal(leftID, leftTitle) = current {
            convertToSplitTab(leftID: leftID, leftTitle: leftTitle)
        }
    }

    /// Dissolves the current split tab into two separate terminal tabs.
    func dissolveSplitTab() {
        guard let idx = terminalItems.firstIndex(where: { $0 == resolvedSelectedTab }),
              case let .split(left, right, leftTitle, rightTitle) = terminalItems[idx] else { return }
        let leftTab = ContentTab.terminal(sessionID: left, title: leftTitle)
        let rightTab = ContentTab.terminal(sessionID: right, title: rightTitle)
        terminalItems.remove(at: idx)
        terminalItems.insert(rightTab, at: idx)
        terminalItems.insert(leftTab, at: idx)
        selectedContentTab = leftTab
        commandRouter.isDualPaneActive = false
        commandRouter.focusedDualPaneID = nil
        sessionStore.activateSession(id: left)
    }

    private func convertToSplitTab(leftID: SessionID, leftTitle: String) {
        let secondary = sessionStore.sessions.first { sid in
            sid.id != leftID && !terminalItems.contains { $0.containsSession(sid.id) }
        } ?? sessionStore.sessions.first { $0.id != leftID }
           ?? sessionStore.createSession(title: "Terminal")
        let splitTab = ContentTab.split(
            left: leftID,
            right: secondary.id,
            leftTitle: leftTitle,
            rightTitle: secondary.title
        )
        if let idx = terminalItems.firstIndex(where: { $0.containsSession(leftID) }) {
            terminalItems[idx] = splitTab
        } else {
            terminalItems.append(splitTab)
        }
        selectedContentTab = splitTab
        focusedSlot = .left
        commandRouter.isDualPaneActive = true
        commandRouter.focusedDualPaneID = leftID
        sessionStore.ensureEngine(for: secondary.id)
    }
}

// Tab persistence is in MainView+TabPersistence.swift
// Session lifecycle helpers are in MainView+SessionSync.swift
