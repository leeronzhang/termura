import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "MainView+Actions")

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

    func openPreviewTab(path: String, name: String) {
        let tab = ContentTab.preview(path, name)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
        persistOpenTabs()
    }

    func openProjectFile(relativePath: String, mode: FileOpenMode) {
        let name = URL(fileURLWithPath: relativePath).lastPathComponent
        switch mode {
        case .diff(let staged, let untracked):
            openDiffTab(path: relativePath, staged: staged, untracked: untracked)
        case .edit:
            openFileTab(path: relativePath, name: name)
        case .preview:
            openPreviewTab(path: relativePath, name: name)
        }
    }

    func closeContentTab(_ tab: ContentTab) {
        switch tab {
        case .terminal:
            // Terminal tabs are not closable from tab bar (managed via sidebar).
            break
        case .note, .diff, .file, .preview:
            openTabs.removeAll { $0 == tab }
            if selectedContentTab == tab {
                // Fall back to the active session's terminal tab.
                selectedContentTab = nil
            }
            persistOpenTabs()
        }
    }

    /// Cmd+W handler: close the active non-terminal tab, or close the session if on a terminal tab.
    func handleCloseTab() {
        let tab = resolvedSelectedTab
        if tab.isClosable {
            closeContentTab(tab)
        } else if tab.isTerminal {
            // Terminal tab — close the session (with confirmation).
            showCloseSessionConfirm = true
        }
    }

    func confirmCloseActiveSession() {
        if let activeID = sessionStore.activeSessionID {
            sessionStore.closeSession(id: activeID)
            // Clear selected tab so it falls back to the next available session.
            if selectedContentTab?.sessionID == activeID {
                selectedContentTab = nil
            }
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
        // Only persist note and file tabs — terminal tabs are derived from sessions,
        // diffs are ephemeral.
        let persistable = openTabs.filter {
            switch $0 {
            case .note, .file, .preview: return true
            case .terminal, .diff: return false
            }
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(persistable)
        } catch {
            logger.warning("Failed to encode open tabs: \(error.localizedDescription)")
            return
        }
        UserDefaults.standard.set(data, forKey: tabsDefaultsKey)
        // Also save the selected tab id for restoration.
        if let tab = selectedContentTab {
            UserDefaults.standard.set(tab.id, forKey: tabsDefaultsKey + ".selected")
        }
    }

    /// Restores previously open tabs from UserDefaults.
    func restoreOpenTabs() {
        guard let data = UserDefaults.standard.data(forKey: tabsDefaultsKey) else { return }
        let restored: [ContentTab]
        do {
            restored = try JSONDecoder().decode([ContentTab].self, from: data)
        } catch {
            logger.warning("Failed to decode open tabs: \(error.localizedDescription)")
            return
        }
        guard !restored.isEmpty else { return }

        for tab in restored where !openTabs.contains(tab) {
            openTabs.append(tab)
        }

        // Restore selected tab if it matches an available tab.
        if let selectedID = UserDefaults.standard.string(forKey: tabsDefaultsKey + ".selected"),
           let match = allTabs.first(where: { $0.id == selectedID }) {
            selectedContentTab = match
        }
    }
}
