import SwiftUI

// MARK: - Session lifecycle helpers

extension MainView {
    func ensureInitialSession() async {
        if sessionStore.state == .idle || sessionStore.state == .loading {
            for await _ in sessionStore.sessionsLoaded.values {
                break
            }
        }
        if sessionStore.activeSessions.isEmpty {
            sessionStore.createSession(title: "Terminal")
        }
        syncTerminalItems()
        // Pin the selected tab to the session whose engine was created during load.
        // terminalItems.first may belong to a different session with no engine yet,
        // which causes resolvedSelectedTab to render emptyState.
        if let activeID = sessionStore.activeSessionID,
           let activeTab = tabManager.terminalItems.first(where: { $0.containsSession(activeID) }) {
            tabManager.selectedContentTab = activeTab
        }
    }

    /// Reconciles `terminalItems` with the current session list.
    /// Adds tabs for new active sessions; removes tabs for deleted or ended sessions.
    /// Also refreshes tab titles when sessions are renamed.
    func syncTerminalItems() {
        let activeIDs = Set(sessionStore.activeSessions.map(\.id))
        var updated = reconcileExistingTabs(activeIDs: activeIDs)
        let tabForActive = appendNewSessionTabs(into: &updated, activeIDs: activeIDs)
        tabManager.terminalItems = updated
        if let newTab = tabForActive {
            tabManager.selectedContentTab = newTab
        } else if let sel = tabManager.selectedContentTab, !allTabs.contains(sel) {
            // Title-only change: selectedContentTab still references the old title
            // (ContentTab equality includes title). Find the updated tab by session ID
            // so a rename doesn't cause an unwanted tab switch.
            if let sid = sel.sessionID,
               let refreshed = updated.first(where: { $0.containsSession(sid) }) {
                tabManager.selectedContentTab = refreshed
            } else if let ids = sel.splitSessionIDs,
                      let refreshed = updated.first(where: { $0.containsSession(ids.left) }) {
                tabManager.selectedContentTab = refreshed
            } else {
                tabManager.selectedContentTab = tabManager.terminalItems.last
            }
        }
    }

    /// Walks existing tabs: drops stale ones, refreshes titles, demotes split to single.
    private func reconcileExistingTabs(activeIDs: Set<SessionID>) -> [ContentTab] {
        let titles = sessionStore.sessionTitles
        var result: [ContentTab] = []
        for item in tabManager.terminalItems {
            switch item {
            case let .terminal(sid, currentTitle):
                guard activeIDs.contains(sid) else { continue }
                let fresh = titles[sid] ?? currentTitle
                result.append(fresh != currentTitle
                    ? .terminal(sessionID: sid, title: fresh)
                    : item)
            case let .split(left, right, lTitle, rTitle):
                let lActive = activeIDs.contains(left)
                let rActive = activeIDs.contains(right)
                if lActive && rActive {
                    let newL = titles[left] ?? lTitle
                    let newR = titles[right] ?? rTitle
                    if newL != lTitle || newR != rTitle {
                        result.append(.split(left: left, right: right, leftTitle: newL, rightTitle: newR))
                    } else {
                        result.append(item)
                    }
                } else if lActive {
                    result.append(.terminal(sessionID: left, title: titles[left] ?? lTitle))
                } else if rActive {
                    result.append(.terminal(sessionID: right, title: titles[right] ?? rTitle))
                }
            default:
                result.append(item)
            }
        }
        return result
    }

    /// Adds tabs for active sessions not yet covered by existing tabs.
    private func appendNewSessionTabs(
        into updated: inout [ContentTab],
        activeIDs: Set<SessionID>
    ) -> ContentTab? {
        let coveredIDs = Set(updated.flatMap { item -> [SessionID] in
            switch item {
            case let .terminal(sid, _): [sid]
            case let .split(left, right, _, _): [left, right]
            default: []
            }
        })
        var tabForActive: ContentTab?
        for session in sessionStore.activeSessions where !coveredIDs.contains(session.id) {
            let tab = ContentTab.terminal(sessionID: session.id, title: session.title)
            updated.append(tab)
            if session.id == sessionStore.activeSessionID { tabForActive = tab }
        }
        return tabForActive
    }
}
