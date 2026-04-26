import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "MainView+Actions")

// MARK: - Command reducer

//
// Single entry point for command-driven UI mutations. Tab open/close/activate
// helpers live in `MainView+TabActions.swift`.

extension MainView {
    /// Single entry point for all command-driven UI mutations.
    /// Called from the unified `.onChange(of: commandRouter.pendingCommand)` in MainView.body.
    func reduce(command: CommandRouter.PendingCommand) {
        switch command {
        case .toggleDualPane: handleToggleDualPane()
        case .closeTab: handleCloseTab()
        case .createNote: handleCreateNote()
        case .toggleSessionInfo: handleToggleSessionInfo()
        case .toggleAgentDashboard: handleToggleAgentDashboard()
        case let .resumeAgent(agentType): handleAgentResume(agentType)
        case let .composerPrefill(text): handleComposerPrefill(text)
        case let .endSession(sid): handleEndSession(sid)
        case let .selectSession(index): handleSelectSession(at: index)
        case let .cycleContentTab(forward): handleCycleContentTab(forward: forward)
        case let .focusDualPane(slot): handleFocusDualPaneDispatch(slot)
        case .swapPanes: handleSwapPanesDispatch()
        case .openLastSilentNote: handleOpenLastSilentNote()
        case let .openNoteTab(noteID): handleOpenNoteTab(noteID: noteID)
        }
    }

    // MARK: - Dual-pane dispatch (context-aware session vs. note)

    private func handleToggleDualPane() {
        if resolvedSelectedTab?.isNote == true {
            toggleNoteSplitTab()
        } else {
            toggleSplitTab()
        }
    }

    private func handleFocusDualPaneDispatch(_ slot: PaneSlot) {
        if commandRouter.isNoteDualPaneActive {
            handleFocusNoteDualPane(slot)
        } else {
            handleFocusDualPane(slot)
        }
    }

    private func handleSwapPanesDispatch() {
        if commandRouter.isNoteDualPaneActive {
            swapNotePanes()
        } else {
            swapPanes()
        }
    }

    private func handleEndSession(_ sid: SessionID) {
        removeTerminalTab(containingSession: sid)
        Task { @MainActor in await sessionStore.endSession(id: sid) }
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
