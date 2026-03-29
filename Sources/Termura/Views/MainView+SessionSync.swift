import SwiftUI

// MARK: - Session lifecycle helpers

extension MainView {
    func ensureInitialSession() async {
        if !sessionStore.hasLoadedPersistedSessions {
            for await _ in sessionStore.sessionsLoaded.values { break }
        }
        if sessionStore.sessions.isEmpty {
            sessionStore.createSession(title: "Terminal")
        }
        syncTerminalItems()
        // Pin the selected tab to the session whose engine was created during load.
        // terminalItems.first may belong to a different session with no engine yet,
        // which causes resolvedSelectedTab to render emptyState.
        if let activeID = sessionStore.activeSessionID,
           let activeTab = terminalItems.first(where: { $0.containsSession(activeID) }) {
            selectedContentTab = activeTab
        }
    }

    /// Reconciles `terminalItems` with the current session list.
    /// Adds tabs for new sessions; dissolves or removes tabs for closed sessions.
    func syncTerminalItems() {
        let allSessionIDs = Set(sessionStore.sessions.map(\.id))
        // Remove tabs for sessions that no longer exist.
        var updated: [ContentTab] = []
        for item in terminalItems {
            switch item {
            case let .terminal(sid, _):
                if allSessionIDs.contains(sid) { updated.append(item) }
                // else: session closed — drop the tab
            case let .split(left, right, leftTitle, rightTitle):
                let leftExists = allSessionIDs.contains(left)
                let rightExists = allSessionIDs.contains(right)
                if leftExists && rightExists {
                    updated.append(item)
                } else if leftExists {
                    updated.append(.terminal(sessionID: left, title: leftTitle))
                } else if rightExists {
                    updated.append(.terminal(sessionID: right, title: rightTitle))
                }
                // else: both gone — drop the tab
            default:
                updated.append(item)
            }
        }
        // Add tabs for sessions not yet represented.
        let coveredIDs = Set(updated.flatMap { item -> [SessionID] in
            switch item {
            case let .terminal(sid, _): return [sid]
            case let .split(left, right, _, _): return [left, right]
            default: return []
            }
        })
        for session in sessionStore.sessions where !coveredIDs.contains(session.id) {
            updated.append(.terminal(sessionID: session.id, title: session.title))
        }
        terminalItems = updated
        // Ensure selected tab is still valid.
        if let sel = selectedContentTab, !allTabs.contains(sel) {
            selectedContentTab = terminalItems.last
        }
    }

    func performSplit(axis: SplitAxis) {
        guard let activeID = sessionStore.activeSessionID else { return }
        let newSession = sessionStore.createSession(title: "Terminal")
        if splitRoot == nil {
            splitRoot = SplitNodeMutations.splitLeaf(
                root: .leaf(activeID),
                targetID: activeID,
                newID: newSession.id,
                axis: axis
            )
        } else if let root = splitRoot {
            splitRoot = SplitNodeMutations.splitLeaf(
                root: root,
                targetID: activeID,
                newID: newSession.id,
                axis: axis
            )
        }
    }

    func performCloseSplitPane() {
        guard let activeID = sessionStore.activeSessionID else { return }
        Task { @MainActor in
            await sessionStore.closeSession(id: activeID)
            // Only update split state if the session was actually removed from the store.
            // closeSession returns without mutating sessions if the DB delete failed.
            guard !sessionStore.sessions.contains(where: { $0.id == activeID }) else { return }
            // Re-read splitRoot after the await — it may have changed during suspension.
            guard let root = splitRoot else { return }
            if let remaining = SplitNodeMutations.removeLeaf(root: root, targetID: activeID) {
                if case .leaf = remaining {
                    splitRoot = nil
                } else {
                    splitRoot = remaining
                }
            } else {
                splitRoot = nil
            }
            syncTerminalItems()
            if let nextID = sessionStore.activeSessionID,
               let tab = terminalItems.first(where: { $0.containsSession(nextID) }) {
                selectedContentTab = tab
            }
        }
    }
}
