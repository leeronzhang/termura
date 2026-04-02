import Foundation

// MARK: - Read-only queries

extension SessionStore {
    /// Derives a human-readable session title from the project root directory basename.
    func defaultSessionTitle() -> String {
        if let root = projectRoot {
            let basename = URL(fileURLWithPath: root).lastPathComponent
            if !basename.isEmpty { return basename }
        }
        return "Terminal"
    }

    func isRestoredSession(id: SessionID) -> Bool {
        restoredSessionIDs.contains(id)
    }

    /// O(1) lookup by ID using the position index.
    func session(id: SessionID) -> SessionRecord? {
        guard let idx = sessionIndex[id] else { return nil }
        return sessions[idx]
    }

    /// Creates a terminal engine for the session if one does not exist yet.
    /// Unlike `activateSession`, does NOT change `activeSessionID`.
    func ensureEngine(for id: SessionID, shell: String? = nil) {
        guard engineStore.engine(for: id) == nil else { return }
        let workingDirectory = session(id: id)?.workingDirectory ?? projectRoot
        engineStore.createEngine(
            for: id,
            shell: shell ?? defaultShell,
            currentDirectory: workingDirectory
        )
    }
}
