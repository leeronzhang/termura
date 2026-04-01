import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "MainView+Actions")

// MARK: - Command reducer

extension MainView {
    /// Single entry point for all command-driven UI mutations.
    /// Called from the unified `.onChange(of: commandRouter.pendingCommand)` in MainView.body.
    func reduce(command: CommandRouter.PendingCommand) {
        switch command {
        case .toggleDualPane:
            toggleSplitTab()
        case .closeTab:
            handleCloseTab()
        case .createNote:
            handleCreateNote()
        case .toggleSessionInfo:
            handleToggleSessionInfo()
        case .toggleAgentDashboard:
            handleToggleAgentDashboard()
        case .resumeAgent(let agentType):
            handleAgentResume(agentType)
        case .composerPrefill(let text):
            handleComposerPrefill(text)
        case .endSession(let sid):
            // Synchronously remove the tab and update selection BEFORE the async endSession
            // to prevent blank state: endSession calls terminateEngine synchronously (before
            // the DB await), so the engine disappears while selectedContentTab still points
            // to the closed tab. Moving the UI update here eliminates that window.
            removeTerminalTab(containingSession: sid)
            Task { @MainActor in
                await sessionStore.endSession(id: sid)
            }
        case .selectSession(let index):
            handleSelectSession(at: index)
        case .cycleContentTab(let forward):
            handleCycleContentTab(forward: forward)
        case .focusDualPane(let slot):
            handleFocusDualPane(slot)
        case .openLastSilentNote:
            handleOpenLastSilentNote()
        }
    }

    private func handleOpenLastSilentNote() {
        guard let noteID = notesViewModel.lastSilentNoteID,
              let note = notesViewModel.notes.first(where: { $0.id == noteID }) else { return }
        commandRouter.selectedSidebarTab = .notes
        openNoteTab(noteID: note.id, title: note.title)
    }

    /// Activate the session at the given 0-based index in the visible (non-ended) session list.
    /// No-op if the index exceeds the number of visible sessions.
    private func handleSelectSession(at index: Int) {
        let visible = sessionStore.activeSessions
        guard index < visible.count else { return }
        activateSessionFromSidebar(visible[index])
    }

    /// Cycle the selected ContentTab forward or backward, wrapping at the ends.
    /// Replicates the ContentTabBar binding setter to keep session/sidebar state in sync.
    private func handleCycleContentTab(forward: Bool) {
        let tabs = allTabs
        guard tabs.count > 1 else { return }
        guard let current = resolvedSelectedTab else { return }
        guard let currentIndex = tabs.firstIndex(of: current) else { return }
        let nextIndex = forward
            ? (currentIndex + 1) % tabs.count
            : (currentIndex - 1 + tabs.count) % tabs.count
        let newTab = tabs[nextIndex]
        selectedContentTab = newTab
        switch newTab {
        case let .terminal(sid, _):
            sessionStore.activateSession(id: sid)
        case let .split(left, right, _, _):
            sessionStore.activateSession(id: focusedSlot == .left ? left : right)
            commandRouter.isDualPaneActive = true
        case .note:
            commandRouter.selectedSidebarTab = .notes
        case .diff, .file, .preview:
            commandRouter.selectedSidebarTab = .project
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
    private func handleToggleSessionInfo() {
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

    /// Pre-fills the Composer with the agent's resume command and opens it.
    /// This is the fallback path — only reached when PTY-level context injection
    /// is unavailable (non-harness builds). No-ops if the feature is disabled,
    /// the Composer is already open, or the editor already contains text.
    private func handleAgentResume(_ agentType: AgentType) {
        let key = AppConfig.AgentResume.autoFillEnabledKey
        let enabled = UserDefaults.standard.object(forKey: key) as? Bool
                      ?? AppConfig.AgentResume.autoFillDefault
        guard enabled else { return }
        guard !commandRouter.showComposer else { return }
        // Skip auto-fill if the agent is already running in this session.
        let sid = focusedPaneSessionID ?? sessionStore.activeSessionID
        if let sid, sessionScope.agentStates.agents[sid] != nil { return }
        guard let editorVM = activeEditorViewModel else { return }
        guard editorVM.currentText.isEmpty else { return }
        let command = agentType.resumeCommand
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
        case let .terminal(sid, _):
            // Remove tab synchronously before async endSession to prevent blank state
            // (endSession terminates the engine synchronously before its DB await).
            removeTerminalTab(containingSession: sid)
            Task { @MainActor in
                await sessionStore.endSession(id: sid)
            }
        case let .split(left, right, _, _):
            // End the focused pane; dissolve the split so the surviving pane continues.
            let sid = focusedPaneSessionID ?? left
            let survivingID = sid == left ? right : left
            removeTerminalTab(containingSession: sid)
            Task { @MainActor in
                await sessionStore.endSession(id: sid)
                sessionStore.activateSession(id: survivingID)
            }
        case .note, .diff, .file, .preview:
            openTabs.removeAll { $0 == tab }
            if selectedContentTab == tab {
                selectedContentTab = terminalItems.last ?? openTabs.first
            }
            persistOpenTabs()
        }
    }

    /// Cmd+W handler: ends the current session if on a terminal/split tab, or closes a non-terminal tab.
    func handleCloseTab() {
        guard let tab = resolvedSelectedTab else { return }
        closeContentTab(tab)
    }

    /// Remove or dissolve the terminal/split tab containing the given session ID.
    func removeTerminalTab(containingSession sid: SessionID) {
        guard let idx = terminalItems.firstIndex(where: { $0.containsSession(sid) }) else { return }
        let item = terminalItems[idx]
        if case let .split(left, right, leftTitle, rightTitle) = item {
            let survivingID = left == sid ? right : left
            let survivingTitle = left == sid ? rightTitle : leftTitle
            let replacement = ContentTab.terminal(sessionID: survivingID, title: survivingTitle)
            terminalItems[idx] = replacement
            selectedContentTab = replacement
            sessionStore.activateSession(id: survivingID)
        } else {
            let wasSelected = selectedContentTab?.containsSession(sid) == true
            terminalItems.remove(at: idx)
            // Only update selection if the removed tab was the selected one; closing a
            // background tab must not silently jump the user away from their current tab.
            if wasSelected {
                selectedContentTab = terminalItems.last ?? openTabs.first
                if let next = selectedContentTab?.sessionID {
                    sessionStore.activateSession(id: next)
                }
            }
        }
    }

    func handleCreateNote() {
        commandRouter.selectedSidebarTab = .notes
        let note = notesViewModel.createNote()
        openNoteTab(noteID: note.id, title: note.title)
    }

    func confirmDeleteSession(id: SessionID) {
        Task { @MainActor in
            await sessionStore.deleteSession(id: id)
            // deleteSession removes from sessions array; syncTerminalItems fires automatically.
        }
    }
}

// MARK: - Session activation (from sidebar)

extension MainView {
    /// Called when the user taps a session in the sidebar.
    /// Ended sessions are reopened; active sessions jump to or open their tab.
    func activateSessionFromSidebar(_ session: SessionRecord) {
        if session.isEnded {
            Task { @MainActor in
                await sessionStore.reopenSession(id: session.id)
                let tab = ContentTab.terminal(sessionID: session.id, title: session.title)
                if !terminalItems.contains(tab) { terminalItems.append(tab) }
                selectedContentTab = tab
            }
            return
        }
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
        // Eagerly create the engine before activateSession to avoid ~120ms blank state from the
        // lazy-creation debounce. ensureEngine is idempotent; activateSession takes the fast path.
        sessionStore.ensureEngine(for: session.id)
        sessionStore.activateSession(id: session.id)
    }
}
