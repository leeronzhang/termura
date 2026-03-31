import SwiftUI

// MARK: - Session lifecycle helpers

extension MainView {
    func ensureInitialSession() async {
        if !sessionStore.hasLoadedPersistedSessions {
            for await _ in sessionStore.sessionsLoaded.values { break }
        }
        if sessionStore.activeSessions.isEmpty {
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
    /// Adds tabs for new active sessions; removes tabs for deleted or ended sessions.
    func syncTerminalItems() {
        let activeSessionIDs = Set(sessionStore.activeSessions.map(\.id))
        // Remove tabs for sessions that no longer exist or have been ended.
        var updated: [ContentTab] = []
        for item in terminalItems {
            switch item {
            case let .terminal(sid, _):
                if activeSessionIDs.contains(sid) { updated.append(item) }
                // else: session deleted or ended — drop the tab
            case let .split(left, right, leftTitle, rightTitle):
                let leftActive = activeSessionIDs.contains(left)
                let rightActive = activeSessionIDs.contains(right)
                if leftActive && rightActive {
                    updated.append(item)
                } else if leftActive {
                    updated.append(.terminal(sessionID: left, title: leftTitle))
                } else if rightActive {
                    updated.append(.terminal(sessionID: right, title: rightTitle))
                }
                // else: both gone — drop the tab
            default:
                updated.append(item)
            }
        }
        // Add tabs for active (non-ended) sessions not yet represented.
        let coveredIDs = Set(updated.flatMap { item -> [SessionID] in
            switch item {
            case let .terminal(sid, _): return [sid]
            case let .split(left, right, _, _): return [left, right]
            default: return []
            }
        })
        var tabForActiveSession: ContentTab?
        for session in sessionStore.activeSessions where !coveredIDs.contains(session.id) {
            let tab = ContentTab.terminal(sessionID: session.id, title: session.title)
            updated.append(tab)
            if session.id == sessionStore.activeSessionID {
                tabForActiveSession = tab
            }
        }
        terminalItems = updated
        // Auto-select the newly created tab if it matches the active session.
        if let newTab = tabForActiveSession {
            selectedContentTab = newTab
        } else if let sel = selectedContentTab, !allTabs.contains(sel) {
            // Ensure selected tab is still valid.
            selectedContentTab = terminalItems.last
        }
    }

}
