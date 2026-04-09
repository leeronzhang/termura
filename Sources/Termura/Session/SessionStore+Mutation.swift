import Foundation

// MARK: - Internal mutation helpers

extension SessionStore {
    /// Rebuilds the full position index from `sessions`, then refreshes all derived state.
    /// O(n) — call only after structural mutations (bulk load, removal, reorder).
    func rebuildSessionIndex() {
        sessionIndex.removeAll(keepingCapacity: true)
        for (i, session) in sessions.enumerated() {
            sessionIndex[session.id] = i
        }
        rebuildDerivedState()
        rebuildSessionTitles()
    }

    /// Appends a session record, updates the O(1) position index, and refreshes derived state.
    func appendSession(_ record: SessionRecord) {
        sessions.append(record)
        sessionIndex[record.id] = sessions.count - 1
        sessionTitles[record.id] = record.title
        rebuildDerivedState()
    }

    /// Mutates a session in place by ID, then refreshes derived state.
    /// Returns the updated record, or nil if not found.
    @discardableResult
    func mutateSession(id: SessionID, _ update: (inout SessionRecord) -> Void) -> SessionRecord? {
        guard let idx = sessionIndex[id] else { return nil }
        update(&sessions[idx])
        // O(1) incremental title update — rebuildDerivedState never touches sessionTitles.
        sessionTitles[id] = sessions[idx].title
        rebuildDerivedState()
        return sessions[idx]
    }

    /// Reorders the sessions array in place and rebuilds the index.
    func reorderSessionsInPlace(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
        for index in sessions.indices {
            sessions[index].orderIndex = index
        }
        rebuildSessionIndex()
    }

    /// Replaces all sessions and rebuilds the index. Use only for rollback in onFailure closures.
    func replaceAllSessions(_ newSessions: [SessionRecord]) {
        sessions = newSessions
        rebuildSessionIndex()
    }

    /// Single O(n) pass over `sessions` that refreshes the filtered derived arrays.
    /// Does NOT touch `sessionTitles` — title maintenance is a separate responsibility:
    ///   - In-place mutations: caller writes `sessionTitles[id] = ...` directly (O(1)).
    ///   - Structural mutations: `rebuildSessionIndex` calls `rebuildSessionTitles()` after this.
    func rebuildDerivedState() {
        var active: [SessionRecord] = []
        var pinned: [SessionRecord] = []
        var activeTree: [SessionRecord] = []
        var ended: [SessionRecord] = []
        for session in sessions {
            if session.isEnded {
                ended.append(session)
            } else {
                active.append(session)
                if session.isPinned { pinned.append(session) } else { activeTree.append(session) }
            }
        }
        activeSessions = active
        pinnedSessions = pinned
        sessionTreeNodes = SessionTreeNode.buildForest(from: activeTree)
        endedSessions = ended
    }

    /// Full O(n) rebuild of `sessionTitles`.
    /// Called only from `rebuildSessionIndex` (structural mutations: delete, reorder, bulk replace).
    /// In-place mutations skip this and update the affected entry directly.
    private func rebuildSessionTitles() {
        var titles: [SessionID: String] = [:]
        titles.reserveCapacity(sessions.count)
        for session in sessions {
            titles[session.id] = session.title
        }
        sessionTitles = titles
    }
}
