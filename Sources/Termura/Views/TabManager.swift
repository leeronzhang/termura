import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "TabManager")

/// Manages the collection of open tabs (terminals, splits, files, notes) and selection state.
/// Extracted from MainView to reduce its view-state bloat.
@Observable
@MainActor
final class TabManager {
    /// Explicitly managed terminal tab list (terminal + split entries).
    var terminalItems: [ContentTab] = []
    /// Which slot is focused within the current split tab.
    var focusedSlot: PaneSlot = .left
    /// Non-terminal tabs (files, notes, diffs).
    var openTabs: [ContentTab] = []
    /// Currently selected tab across all lists.
    var selectedContentTab: ContentTab?

    // Dependencies (set via inject)
    var sessionStore: (any SessionStoreProtocol)?
    var commandRouter: CommandRouter?
    var notesViewModel: NotesViewModel?

    func inject(sessionStore: any SessionStoreProtocol, commandRouter: CommandRouter) {
        self.sessionStore = sessionStore
        self.commandRouter = commandRouter
    }

    // MARK: - Selected Tab Helpers

    var resolvedSelectedTab: ContentTab? {
        selectedContentTab ?? terminalItems.last ?? openTabs.first
    }

    var isInSplitMode: Bool { resolvedSelectedTab?.isSplit ?? false }

    /// Builds a lookup of every session currently in a split tab, mapping to its partner info.
    func buildSplitMemberships() -> [SessionID: SplitMembership] {
        var result: [SessionID: SplitMembership] = [:]
        let activeID = resolvedSelectedTab?.id
        for tab in terminalItems {
            guard case let .split(left, right, leftTitle, rightTitle) = tab else { continue }
            let isActive = tab.id == activeID
            result[left] = SplitMembership(
                partnerSessionID: right, partnerTitle: rightTitle,
                isActiveTab: isActive, paneSlot: .left
            )
            result[right] = SplitMembership(
                partnerSessionID: left, partnerTitle: leftTitle,
                isActiveTab: isActive, paneSlot: .right
            )
        }
        return result
    }

    var leftPaneSessionID: SessionID? {
        guard case let .split(left, _, _, _) = resolvedSelectedTab else { return nil }
        return left
    }

    var rightPaneSessionID: SessionID? {
        guard case let .split(_, right, _, _) = resolvedSelectedTab else { return nil }
        return right
    }

    var focusedPaneSessionID: SessionID? {
        focusedSlot == .left ? leftPaneSessionID : rightPaneSessionID
    }

    // MARK: - Note split accessors

    var leftPaneNoteID: NoteID? {
        guard case let .noteSplit(left, _, _, _) = resolvedSelectedTab else { return nil }
        return left
    }

    var rightPaneNoteID: NoteID? {
        guard case let .noteSplit(_, right, _, _) = resolvedSelectedTab else { return nil }
        return right
    }

    // MARK: - Tab Operations

    func openNoteTab(noteID: NoteID, title: String) {
        let tab = ContentTab.note(noteID: noteID, title: title)
        if let idx = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs[idx] = tab
        } else {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }

    func openDiffTab(path: String, staged: Bool, untracked: Bool = false) {
        let tab = ContentTab.diff(path: path, isStaged: staged, isUntracked: untracked)
        if let idx = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs[idx] = tab
        } else {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }

    func openFileTab(path: String, name: String) {
        let tab = ContentTab.file(path: path, name: name)
        if let idx = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs[idx] = tab
        } else {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }

    func openPreviewTab(path: String, name: String) {
        let tab = ContentTab.preview(path: path, name: name)
        if let idx = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs[idx] = tab
        } else {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }

    func closeTab(_ tab: ContentTab) {
        switch tab {
        case let .terminal(sid, _):
            removeTerminalTab(containingSession: sid)
            Task { @MainActor in
                await sessionStore?.endSession(id: sid)
            }
        case let .split(left, right, _, _):
            let sid = focusedPaneSessionID ?? left
            let survivingID = sid == left ? right : left
            removeTerminalTab(containingSession: sid)
            Task { @MainActor in
                await sessionStore?.endSession(id: sid)
                sessionStore?.activateSession(id: survivingID)
            }
        case .note, .noteSplit, .diff, .file, .preview:
            openTabs.removeAll { $0 == tab }
            if selectedContentTab == tab {
                selectedContentTab = terminalItems.last ?? openTabs.first
            }
        }
    }

    func removeTerminalTab(containingSession sid: SessionID) {
        guard let idx = terminalItems.firstIndex(where: { $0.containsSession(sid) }) else { return }
        let item = terminalItems[idx]
        if case let .split(left, right, leftTitle, rightTitle) = item {
            let survivingID = left == sid ? right : left
            let survivingTitle = left == sid ? rightTitle : leftTitle
            let replacement = ContentTab.terminal(sessionID: survivingID, title: survivingTitle)
            terminalItems[idx] = replacement
            selectedContentTab = replacement
            sessionStore?.activateSession(id: survivingID)
        } else {
            let wasSelected = selectedContentTab?.containsSession(sid) == true
            terminalItems.remove(at: idx)
            if wasSelected {
                selectedContentTab = terminalItems.last ?? openTabs.first
                if let next = selectedContentTab?.sessionID {
                    sessionStore?.activateSession(id: next)
                }
            }
        }
    }

    func activateSessionFromSidebar(_ session: SessionRecord) {
        if session.isEnded {
            Task { @MainActor in
                await sessionStore?.reopenSession(id: session.id)
                let tab = ContentTab.terminal(sessionID: session.id, title: session.title)
                if let idx = terminalItems.firstIndex(where: { $0.containsSession(session.id) }) {
                    terminalItems[idx] = tab
                } else {
                    terminalItems.append(tab)
                }
                selectedContentTab = tab
            }
            return
        }
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

        sessionStore?.ensureEngine(for: session.id, shell: nil)
        sessionStore?.activateSession(id: session.id)
    }

    func cycleContentTab(forward: Bool) {
        let tabs = allTabs
        guard tabs.count > 1 else { return }
        guard let current = resolvedSelectedTab else { return }
        guard let currentIndex = tabs.firstIndex(of: current) else { return }
        let nextIndex = forward
            ? (currentIndex + 1) % tabs.count
            : (currentIndex - 1 + tabs.count) % tabs.count
        let newTab = tabs[nextIndex]
        selectedContentTab = newTab

        // Side effects usually handled by View listeners, but TabManager can do it too.
        switch newTab {
        case let .terminal(sid, _):
            sessionStore?.activateSession(id: sid)
            commandRouter?.selectedSidebarTab = .sessions
        case let .split(left, right, _, _):
            sessionStore?.activateSession(id: focusedSlot == .left ? left : right)
            commandRouter?.isDualPaneActive = true
            commandRouter?.selectedSidebarTab = .sessions
        case .note, .noteSplit:
            commandRouter?.selectedSidebarTab = .notes
        case .diff, .file, .preview:
            commandRouter?.selectedSidebarTab = .project
        }
    }

    private var allTabs: [ContentTab] {
        terminalItems + openTabs
    }
}
