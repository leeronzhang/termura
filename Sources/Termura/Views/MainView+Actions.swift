import SwiftUI

// MARK: - Tab management

extension MainView {
    func openNoteTab(noteID: NoteID, title: String) {
        let tab = ContentTab.note(noteID, title)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }

    func closeContentTab(_ tab: ContentTab) {
        switch tab {
        case .terminal:
            // Active session requires confirmation
            if sessionStore.activeSessionID != nil {
                showCloseSessionConfirm = true
            }
        case .note:
            openTabs.removeAll { $0 == tab }
            if selectedContentTab == tab {
                selectedContentTab = .terminal
            }
        }
    }

    func confirmCloseActiveSession() {
        if let activeID = sessionStore.activeSessionID {
            sessionStore.closeSession(id: activeID)
        }
    }
}

// MARK: - Helpers

extension MainView {
    func ensureInitialSession() async {
        // Wait for persisted sessions to be loaded before deciding
        // whether to create a fresh session.
        if !sessionStore.hasLoadedPersistedSessions {
            for await loaded in sessionStore.$hasLoadedPersistedSessions.values where loaded {
                break
            }
        }
        if sessionStore.sessions.isEmpty {
            sessionStore.createSession(title: "Terminal")
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
        guard let activeID = sessionStore.activeSessionID,
              let root = splitRoot else { return }
        if let remaining = SplitNodeMutations.removeLeaf(root: root, targetID: activeID) {
            if case .leaf = remaining {
                splitRoot = nil
            } else {
                splitRoot = remaining
            }
        } else {
            splitRoot = nil
        }
        sessionStore.closeSession(id: activeID)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleSidebar = Notification.Name("com.termura.toggleSidebar")
    static let showShellIntegrationOnboarding = Notification.Name("com.termura.showShellOnboarding")
}
