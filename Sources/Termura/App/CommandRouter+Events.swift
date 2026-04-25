import Foundation

extension CommandRouter {
    enum PendingCommand: Equatable {
        case toggleDualPane
        case closeTab
        case createNote
        case toggleSessionInfo
        case toggleAgentDashboard
        /// Pre-fills the Composer with the agent's default launch command and opens it.
        /// Fired once per restored session when the first shell prompt is detected.
        case resumeAgent(AgentType)
        /// Pre-fills the Composer with a quoted selection from the terminal output.
        /// Opens the Composer if not already visible, or appends if it is.
        case composerPrefill(text: String)
        /// Terminate the PTY for the given session and remove its tab.
        /// Record is preserved in the sidebar as ended; session can be reopened.
        case endSession(SessionID)
        /// Activate the session at the given 0-based index in the visible (non-ended) session list.
        case selectSession(index: Int)
        /// Cycle the selected ContentTab forward or backward by one position.
        case cycleContentTab(forward: Bool)
        /// Focus the specified pane in dual-pane mode. No-op in single-pane mode.
        case focusDualPane(PaneSlot)
        /// Swap left and right panes in the current split tab.
        case swapPanes
        /// Open the most recently silently-created note (e.g. via "Send to Notes" toast tap).
        case openLastSilentNote
        /// Open a specific note tab by ID (used by LinkRouter for terminal Cmd+Click on .md files).
        case openNoteTab(noteID: NoteID)
    }

    // MARK: - Chunk completed callbacks

    /// Register a handler to be called when any OutputStore appends a chunk.
    /// Returns a token that MUST be stored and passed to `removeChunkHandler(token:)` on teardown.
    func onChunkCompleted(_ handler: @escaping (OutputChunk) -> Void) -> UUID {
        let token = UUID()
        chunkHandlers[token] = handler
        return token
    }

    /// Unregister a previously registered handler. Safe to call with an unknown token.
    func removeChunkHandler(token: UUID) {
        chunkHandlers.removeValue(forKey: token)
    }

    /// Called by OutputStore when a chunk is appended.
    func notifyChunkCompleted(_ chunk: OutputChunk) {
        for handler in chunkHandlers.values {
            handler(chunk)
        }
    }
}
