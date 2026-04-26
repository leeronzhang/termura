import Foundation
import SwiftUI

// MARK: - Tab management

//
// Open / close / activate handlers for ContentTabs (notes, files, diffs,
// previews, terminals). Split out of MainView+Actions.swift to keep that
// file's command-reducer narrative compact (CLAUDE.md §6.1).

extension MainView {
    func openNoteTab(noteID: NoteID, title: String) {
        let originSidebar = commandRouter.selectedSidebarTab
        tabManager.openNoteTab(noteID: noteID, title: title)
        if let tab = tabManager.selectedContentTab, isTabAppropriate(tab, for: originSidebar) {
            lastContentTabBySidebarTab[originSidebar] = tab
        }
        persistOpenTabs()
    }

    func openDiffTab(path: String, staged: Bool, untracked: Bool = false) {
        tabManager.openDiffTab(path: path, staged: staged, untracked: untracked)
        persistOpenTabs()
    }

    func openFileTab(path: String, name: String) {
        tabManager.openFileTab(path: path, name: name)
        persistOpenTabs()
    }

    func openPreviewTab(path: String, name: String) {
        tabManager.openPreviewTab(path: path, name: name)
        persistOpenTabs()
    }

    func openProjectFile(relativePath: String, mode: FileOpenMode) {
        // Capture the originating sidebar before the tab is created, because
        // TabManager.selectedContentTab triggers sidebar sync via onSelectedContentTabChange.
        let originSidebar = commandRouter.selectedSidebarTab
        let name = URL(fileURLWithPath: relativePath).lastPathComponent
        switch mode {
        case let .diff(staged, untracked):
            openDiffTab(path: relativePath, staged: staged, untracked: untracked)
        case .edit:
            openFileTab(path: relativePath, name: name)
        case .preview:
            openPreviewTab(path: relativePath, name: name)
        }
        // Synchronously track under the originating sidebar. The deferred onChange-based
        // trackContentTabForSidebarTab is unreliable because selectedSidebarTab may have
        // already auto-switched (e.g. ContentTabBar setter changes sidebar to .project
        // for file tabs) by the time the onChange fires.
        if let tab = tabManager.selectedContentTab, isTabAppropriate(tab, for: originSidebar) {
            lastContentTabBySidebarTab[originSidebar] = tab
        }
    }

    func closeContentTab(_ tab: ContentTab) {
        let sidebar = commandRouter.selectedSidebarTab
        tabManager.closeTab(tab)
        // Clear stale sidebar memory so restore doesn't re-select the closed tab.
        if lastContentTabBySidebarTab[sidebar]?.id == tab.id {
            lastContentTabBySidebarTab[sidebar] = nil
        }
        // If the fallback tab doesn't belong to the current sidebar, find a
        // sibling tab of the same type. If none remain, show the empty state
        // instead of auto-opening new content (restoreNotesTab would reopen a
        // note the user just closed).
        if let newTab = selectedContentTab, !isTabAppropriate(newTab, for: sidebar) {
            let sibling = tabManager.openTabs.last(where: { isTabAppropriate($0, for: sidebar) })
            if let sibling {
                selectAndActivate(sibling, for: sidebar)
            } else {
                tabManager.selectedContentTab = nil
                sidebarShowsEmpty.insert(sidebar)
            }
        }
        // Deselect the note in the sidebar list when its tab is closed.
        if case let .note(noteID, _) = tab, notesViewModel.selectedNoteID == noteID {
            notesViewModel.selectedNoteID = nil
        }
        persistOpenTabs()
    }

    /// Cmd+W handler: ends the current session if on a terminal/split tab, or closes a non-terminal tab.
    func handleCloseTab() {
        guard let tab = resolvedSelectedTab else { return }
        closeContentTab(tab)
    }

    /// Remove or dissolve the terminal/split tab containing the given session ID.
    func removeTerminalTab(containingSession sid: SessionID) {
        tabManager.removeTerminalTab(containingSession: sid)
        persistOpenTabs()
    }

    func handleCreateNote() {
        commandRouter.selectedSidebarTab = .notes
        let note = notesViewModel.createNote()
        openNoteTab(noteID: note.id, title: note.title)
    }

    func confirmDeleteSession(id: SessionID) {
        Task { @MainActor in
            await sessionStore.deleteSession(id: id)
            // deleteSession removes from sessions array; syncTerminalItems fires automatically.
        }
    }
}

// MARK: - Session activation (from sidebar)

extension MainView {
    /// Called when the user taps a session in the sidebar.
    /// Ended sessions are reopened; active sessions jump to or open their tab.
    func activateSessionFromSidebar(_ session: SessionRecord) {
        let originSidebar = commandRouter.selectedSidebarTab
        tabManager.activateSessionFromSidebar(session)
        if let tab = tabManager.selectedContentTab, isTabAppropriate(tab, for: originSidebar) {
            lastContentTabBySidebarTab[originSidebar] = tab
        }
        persistOpenTabs()
    }
}
