import SwiftUI

// MARK: - Tab management

extension MainView {
    func openNoteTab(noteID: NoteID, title: String) {
        let tab = ContentTab.note(noteID, title)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
        persistOpenTabs()
    }

    func openDiffTab(path: String, staged: Bool, untracked: Bool = false) {
        let tab = ContentTab.diff(path, staged, untracked)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }

    func openFileTab(path: String, name: String) {
        let tab = ContentTab.file(path, name)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
        persistOpenTabs()
    }

    func openProjectFile(relativePath: String, mode: FileOpenMode) {
        switch mode {
        case .diff(let staged, let untracked):
            openDiffTab(path: relativePath, staged: staged, untracked: untracked)
        case .edit:
            let name = URL(fileURLWithPath: relativePath).lastPathComponent
            openFileTab(path: relativePath, name: name)
        }
    }

    func closeContentTab(_ tab: ContentTab) {
        switch tab {
        case .terminal:
            // Active session requires confirmation
            if sessionStore.activeSessionID != nil {
                showCloseSessionConfirm = true
            }
        case .note, .diff, .file:
            openTabs.removeAll { $0 == tab }
            if selectedContentTab == tab {
                selectedContentTab = .terminal
            }
            persistOpenTabs()
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

// MARK: - Tab persistence

extension MainView {
    /// UserDefaults key for open tabs, scoped to the current project.
    private var tabsDefaultsKey: String {
        "openTabs-\(sessionStore.projectRoot)"
    }

    /// Saves persistable tabs (note/file) to UserDefaults.
    func persistOpenTabs() {
        // Only persist note and file tabs — diffs are ephemeral.
        let persistable = openTabs.filter {
            switch $0 {
            case .note, .file: return true
            case .terminal, .diff: return false
            }
        }
        guard let data = try? JSONEncoder().encode(persistable) else { return }
        UserDefaults.standard.set(data, forKey: tabsDefaultsKey)
        // Also save the selected tab id for restoration.
        UserDefaults.standard.set(selectedContentTab.id, forKey: tabsDefaultsKey + ".selected")
    }

    /// Restores previously open tabs from UserDefaults.
    func restoreOpenTabs() {
        guard let data = UserDefaults.standard.data(forKey: tabsDefaultsKey),
              let restored = try? JSONDecoder().decode([ContentTab].self, from: data),
              !restored.isEmpty else { return }

        for tab in restored where !openTabs.contains(tab) {
            openTabs.append(tab)
        }

        // Restore selected tab if it matches a restored tab.
        if let selectedID = UserDefaults.standard.string(forKey: tabsDefaultsKey + ".selected"),
           let match = openTabs.first(where: { $0.id == selectedID }) {
            selectedContentTab = match
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleSidebar = Notification.Name("com.termura.toggleSidebar")
    static let showShellIntegrationOnboarding = Notification.Name("com.termura.showShellOnboarding")
    static let projectGitStatusChanged = Notification.Name("com.termura.projectGitStatusChanged")
}
