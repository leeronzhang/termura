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
        case let .diff(staged, untracked):
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

    /// Toggle dual-pane mode: side-by-side view of two sessions.
    func toggleDualPane() {
        if splitSessionID != nil {
            splitSessionID = nil
            focusedPaneID = nil
            commandRouter.isDualPaneActive = false
            commandRouter.focusedDualPaneID = nil
        } else {
            guard let activeID = sessionStore.activeSessionID else { return }
            // Pick the first session that is not the active one.
            let candidate = sessionStore.sessions.first { $0.id != activeID }
            guard let secondary = candidate else { return }
            splitSessionID = secondary.id
            focusedPaneID = activeID
            commandRouter.isDualPaneActive = true
            commandRouter.focusedDualPaneID = activeID
            sessionStore.ensureEngine(for: secondary.id)
        }
    }

    /// Called from sidebar when a session is tapped while dual-pane is active.
    func setDualPaneSecondary(id: SessionID) {
        guard splitSessionID != nil else { return }
        guard id != sessionStore.activeSessionID else { return }
        splitSessionID = id
        sessionStore.ensureEngine(for: id)
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
            case .note, .file, .preview: true
            case .terminal, .diff: false
            }
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(persistable)
        } catch {
            // Non-critical: tab persistence is cosmetic; tabs will be re-created on next use.
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
            // Non-critical: tab restoration is cosmetic; user starts with a clean tab set.
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
