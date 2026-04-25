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
        case let .resumeAgent(agentType):
            handleAgentResume(agentType)
        case let .composerPrefill(text):
            handleComposerPrefill(text)
        case let .endSession(sid):
            // Synchronously remove the tab and update selection BEFORE the async endSession
            // to prevent blank state: endSession calls terminateEngine synchronously (before
            // the DB await), so the engine disappears while selectedContentTab still points
            // to the closed tab. Moving the UI update here eliminates that window.
            removeTerminalTab(containingSession: sid)
            Task { @MainActor in
                await sessionStore.endSession(id: sid)
            }
        case let .selectSession(index):
            handleSelectSession(at: index)
        case let .cycleContentTab(forward):
            handleCycleContentTab(forward: forward)
        case let .focusDualPane(slot):
            handleFocusDualPane(slot)
        case .swapPanes:
            swapPanes()
        case .openLastSilentNote:
            handleOpenLastSilentNote()
        case let .openNoteTab(noteID):
            handleOpenNoteTab(noteID: noteID)
        }
    }

    private func handleOpenLastSilentNote() {
        guard let noteID = notesViewModel.lastSilentNoteID,
              let note = notesViewModel.notes.first(where: { $0.id == noteID }) else { return }
        commandRouter.selectedSidebarTab = .notes
        openNoteTab(noteID: note.id, title: note.title)
    }

    private func handleOpenNoteTab(noteID: NoteID) {
        guard let note = notesViewModel.notes.first(where: { $0.id == noteID }) else { return }
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
        tabManager.cycleContentTab(forward: forward)
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
        let enabled = userDefaults.object(forKey: key) as? Bool
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
        let originSidebar = commandRouter.selectedSidebarTab
        tabManager.openNoteTab(noteID: noteID, title: title)
        if let tab = tabManager.selectedContentTab, isTabAppropriate(tab, for: originSidebar) {
            lastContentTabBySidebarTab[originSidebar] = tab
        }
        persistOpenTabs()
    }

    func openDiffTab(path: String, staged: Bool, untracked: Bool = false) {
        tabManager.openDiffTab(path: path, staged: staged, untracked: untracked)
        persistOpenTabs()
    }

    func openFileTab(path: String, name: String) {
        tabManager.openFileTab(path: path, name: name)
        persistOpenTabs()
    }

    func openPreviewTab(path: String, name: String) {
        tabManager.openPreviewTab(path: path, name: name)
        persistOpenTabs()
    }

    func openProjectFile(relativePath: String, mode: FileOpenMode) {
        // Capture the originating sidebar before the tab is created, because
        // TabManager.selectedContentTab triggers sidebar sync via onSelectedContentTabChange.
        let originSidebar = commandRouter.selectedSidebarTab
        let name = URL(fileURLWithPath: relativePath).lastPathComponent
        switch mode {
        case let .diff(staged, untracked):
            openDiffTab(path: relativePath, staged: staged, untracked: untracked)
        case .edit:
            openFileTab(path: relativePath, name: name)
        case .preview:
            openPreviewTab(path: relativePath, name: name)
        }
        // Synchronously track under the originating sidebar. The deferred onChange-based
        // trackContentTabForSidebarTab is unreliable because selectedSidebarTab may have
        // already auto-switched (e.g. ContentTabBar setter changes sidebar to .project
        // for file tabs) by the time the onChange fires.
        if let tab = tabManager.selectedContentTab, isTabAppropriate(tab, for: originSidebar) {
            lastContentTabBySidebarTab[originSidebar] = tab
        }
    }

    func closeContentTab(_ tab: ContentTab) {
        let sidebar = commandRouter.selectedSidebarTab
        tabManager.closeTab(tab)
        // Clear stale sidebar memory so restore doesn't re-select the closed tab.
        if lastContentTabBySidebarTab[sidebar]?.id == tab.id {
            lastContentTabBySidebarTab[sidebar] = nil
        }
        // If the fallback tab doesn't belong to the current sidebar, find a
        // sibling tab of the same type. If none remain, show the empty state
        // instead of auto-opening new content (restoreNotesTab would reopen a
        // note the user just closed).
        if let newTab = selectedContentTab, !isTabAppropriate(newTab, for: sidebar) {
            let sibling = tabManager.openTabs.last(where: { isTabAppropriate($0, for: sidebar) })
            if let sibling {
                selectAndActivate(sibling, for: sidebar)
            } else {
                sidebarShowsEmpty.insert(sidebar)
            }
        }
        persistOpenTabs()
    }

    /// Cmd+W handler: ends the current session if on a terminal/split tab, or closes a non-terminal tab.
    func handleCloseTab() {
        guard let tab = resolvedSelectedTab else { return }
        closeContentTab(tab)
    }

    /// Remove or dissolve the terminal/split tab containing the given session ID.
    func removeTerminalTab(containingSession sid: SessionID) {
        tabManager.removeTerminalTab(containingSession: sid)
        persistOpenTabs()
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
        let originSidebar = commandRouter.selectedSidebarTab
        tabManager.activateSessionFromSidebar(session)
        if let tab = tabManager.selectedContentTab, isTabAppropriate(tab, for: originSidebar) {
            lastContentTabBySidebarTab[originSidebar] = tab
        }
        persistOpenTabs()
    }
}
