import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "MainView+Actions")

// MARK: - Tab management

extension MainView {
    func openNoteTab(noteID: NoteID, title: String) {
        let tab = ContentTab.note(noteID: noteID, title: title)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
        persistOpenTabs()
    }

    func openDiffTab(path: String, staged: Bool, untracked: Bool = false) {
        let tab = ContentTab.diff(path: path, isStaged: staged, isUntracked: untracked)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }

    func openFileTab(path: String, name: String) {
        let tab = ContentTab.file(path: path, name: name)
        if !openTabs.contains(tab) {
            openTabs.append(tab)
        }
        selectedContentTab = tab
        persistOpenTabs()
    }

    func openPreviewTab(path: String, name: String) {
        let tab = ContentTab.preview(path: path, name: name)
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
        case .terminal, .split:
            // Managed via sidebar / session lifecycle, not closable from tab bar.
            break
        case .note, .diff, .file, .preview:
            openTabs.removeAll { $0 == tab }
            if selectedContentTab == tab {
                selectedContentTab = nil
            }
            persistOpenTabs()
        }
    }

    /// Cmd+W handler: close focused session if on a terminal/split tab, or close a non-terminal tab.
    func handleCloseTab() {
        let tab = resolvedSelectedTab
        if tab.isClosable {
            closeContentTab(tab)
        } else if tab.isTerminal || tab.isSplit {
            showCloseSessionConfirm = true
        }
    }

    func confirmCloseActiveSession() {
        let sessionID = focusedPaneSessionID ?? sessionStore.activeSessionID
        guard let sid = sessionID else { return }
        // If closing a session that is part of a split tab, dissolve to single.
        if let idx = terminalItems.firstIndex(where: { $0.containsSession(sid) }) {
            let item = terminalItems[idx]
            if case let .split(left, right, leftTitle, rightTitle) = item {
                // Replace split with the surviving single session tab.
                let survivingID = left == sid ? right : left
                let survivingTitle = left == sid ? rightTitle : leftTitle
                let replacement = ContentTab.terminal(sessionID: survivingID, title: survivingTitle)
                terminalItems[idx] = replacement
                selectedContentTab = replacement
                sessionStore.activateSession(id: survivingID)
            } else {
                // .terminal tab — remove it.
                terminalItems.remove(at: idx)
                selectedContentTab = terminalItems.last ?? openTabs.first
                if let next = selectedContentTab?.sessionID {
                    sessionStore.activateSession(id: next)
                }
            }
        }
        sessionStore.closeSession(id: sid)
    }
}

// MARK: - Session activation (from sidebar)

extension MainView {
    /// Called when the user taps a session in the sidebar.
    /// Jumps to the existing tab containing the session, or opens a new terminal tab.
    func activateSessionFromSidebar(_ session: SessionRecord) {
        if let tab = terminalItems.first(where: { $0.containsSession(session.id) }) {
            selectedContentTab = tab
            if case let .split(left, _, _, _) = tab {
                focusedSlot = session.id == left ? .left : .right
            }
        } else {
            let tab = ContentTab.terminal(sessionID: session.id, title: session.title)
            terminalItems.append(tab)
            selectedContentTab = tab
        }
        sessionStore.activateSession(id: session.id)
    }
}

// MARK: - Split tab management

extension MainView {
    /// Toggles the current terminal tab between single and split (two-pane) mode.
    func toggleSplitTab() {
        let current = resolvedSelectedTab
        if current.isSplit {
            dissolveSplitTab()
        } else if case let .terminal(leftID, leftTitle) = current {
            convertToSplitTab(leftID: leftID, leftTitle: leftTitle)
        }
    }

    /// Dissolves the current split tab into two separate terminal tabs.
    func dissolveSplitTab() {
        guard let idx = terminalItems.firstIndex(where: { $0 == resolvedSelectedTab }),
              case let .split(left, right, leftTitle, rightTitle) = terminalItems[idx] else { return }
        let leftTab = ContentTab.terminal(sessionID: left, title: leftTitle)
        let rightTab = ContentTab.terminal(sessionID: right, title: rightTitle)
        terminalItems.remove(at: idx)
        terminalItems.insert(rightTab, at: idx)
        terminalItems.insert(leftTab, at: idx)
        selectedContentTab = leftTab
        commandRouter.isDualPaneActive = false
        commandRouter.focusedDualPaneID = nil
        sessionStore.activateSession(id: left)
    }

    private func convertToSplitTab(leftID: SessionID, leftTitle: String) {
        let secondary = sessionStore.sessions.first { sid in
            sid.id != leftID && !terminalItems.contains { $0.containsSession(sid.id) }
        } ?? sessionStore.sessions.first { $0.id != leftID }
           ?? sessionStore.createSession(title: "Terminal")
        let splitTab = ContentTab.split(
            left: leftID,
            right: secondary.id,
            leftTitle: leftTitle,
            rightTitle: secondary.title
        )
        if let idx = terminalItems.firstIndex(where: { $0.containsSession(leftID) }) {
            terminalItems[idx] = splitTab
        } else {
            terminalItems.append(splitTab)
        }
        selectedContentTab = splitTab
        focusedSlot = .left
        commandRouter.isDualPaneActive = true
        commandRouter.focusedDualPaneID = leftID
        sessionStore.ensureEngine(for: secondary.id)
    }
}

// MARK: - Helpers

extension MainView {
    func ensureInitialSession() async {
        if !sessionStore.hasLoadedPersistedSessions {
            for await loaded in sessionStore.$hasLoadedPersistedSessions.values where loaded {
                break
            }
        }
        if sessionStore.sessions.isEmpty {
            sessionStore.createSession(title: "Terminal")
        }
        syncTerminalItems()
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

// Tab persistence is in MainView+TabPersistence.swift
