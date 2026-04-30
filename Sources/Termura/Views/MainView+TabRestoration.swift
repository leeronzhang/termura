import SwiftUI

// MARK: - Per-sidebar restore

extension MainView {
    /// Sessions: restore the last terminal/split tab, or fall back to the active terminal.
    /// Sessions should never show empty state as long as at least one session exists.
    func restoreSessionsTab() {
        if let saved = lastContentTabBySidebarTab[.sessions],
           saved.isTerminal || saved.isSplit,
           let live = findLiveTab(matching: saved) {
            selectAndActivate(live, for: .sessions)
            return
        }
        // Fall back to the active terminal session.
        let activeTab = sessionStore.activeSessionID.flatMap { activeID in
            terminalItems.first(where: { $0.containsSession(activeID) })
        } ?? terminalItems.first
        if let tab = activeTab {
            selectAndActivate(tab, for: .sessions)
        } else {
            sidebarShowsEmpty.insert(.sessions)
        }
    }

    /// Notes: restore saved → scan open note tabs → auto-open first note → empty.
    func restoreNotesTab() {
        if let saved = lastContentTabBySidebarTab[.notes],
           let live = findLiveTab(matching: saved) {
            selectAndActivate(live, for: .notes)
            return
        }
        // Fallback: any open note tab.
        if let noteTab = tabManager.openTabs.last(where: { $0.isNote }) {
            selectAndActivate(noteTab, for: .notes)
            return
        }
        // Auto-open the most recent note (may be empty if notes load asynchronously).
        if let recent = notesViewModel.notes.first {
            tabManager.openNoteTab(noteID: recent.id, title: recent.title)
            sidebarShowsEmpty.remove(.notes)
            return
        }
        sidebarShowsEmpty.insert(.notes)
    }

    /// Project: restore saved tab or empty state. Skips harness rule files.
    func restoreProjectTab() {
        if let saved = lastContentTabBySidebarTab[.project],
           saved.isProjectContent,
           !isHarnessRuleFile(saved),
           let live = findLiveTab(matching: saved) {
            selectAndActivate(live, for: .project)
            return
        }
        sidebarShowsEmpty.insert(.project)
    }

    /// Harness: restore saved tab or empty state.
    func restoreHarnessTab() {
        if let saved = lastContentTabBySidebarTab[.harness],
           let live = findLiveTab(matching: saved) {
            selectAndActivate(live, for: .harness)
            return
        }
        sidebarShowsEmpty.insert(.harness)
    }

    /// Selects the tab, clears empty state, and activates the session if applicable.
    func selectAndActivate(_ tab: ContentTab, for sidebar: SidebarTab) {
        sidebarShowsEmpty.remove(sidebar)
        tabManager.selectedContentTab = tab
        activateRestoredSession(tab)
    }

    /// Sync activeSessionID when restoring a terminal or split tab.
    func activateRestoredSession(_ tab: ContentTab) {
        switch tab {
        case let .terminal(sid, _):
            sessionStore.activateSession(id: sid)
        case let .split(left, right, _, _):
            // Restore the user's last focused slot for this split before activating
            // the corresponding session, so re-entry doesn't snap back to .left.
            let slot = tabManager.restoredFocusedSlot(for: tab)
            tabManager.focusedSlot = slot
            sessionStore.activateSession(id: slot == .left ? left : right)
        default:
            break
        }
    }
}
