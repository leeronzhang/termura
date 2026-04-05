import OSLog
import SwiftUI

private let persistLogger = Logger(subsystem: "com.termura.app", category: "MainView+TabPersistence")

// MARK: - Tab persistence

extension MainView {
    var tabsDefaultsKey: String {
        AppConfig.UserDefaultsKeys.openTabs(
            projectRoot: sessionStore.projectRoot ?? "default"
        )
    }

    func persistOpenTabs() {
        // Only persist note and file tabs — terminal/split/diff tabs are ephemeral or session-derived.
        let persistable = openTabs.filter {
            switch $0 {
            case .note, .file, .preview: true
            case .terminal, .split, .diff: false
            }
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(persistable)
        } catch {
            persistLogger.warning("Failed to encode open tabs: \(error.localizedDescription)")
            return
        }
        UserDefaults.standard.set(data, forKey: tabsDefaultsKey)
        if let tab = selectedContentTab {
            let selectedKey = AppConfig.UserDefaultsKeys.openTabsSelected(
                projectRoot: sessionStore.projectRoot ?? "default"
            )
            UserDefaults.standard.set(tab.id, forKey: selectedKey)
        }
        // Persist per-sidebar tab memory so sidebar restore works across launches.
        let memoryKey = AppConfig.UserDefaultsKeys.sidebarTabMemory(
            projectRoot: sessionStore.projectRoot ?? "default"
        )
        let sidebarMemory: [String: String] = lastContentTabBySidebarTab.reduce(into: [:]) { result, pair in
            result[pair.key.rawValue] = pair.value.id
        }
        UserDefaults.standard.set(sidebarMemory, forKey: memoryKey)
    }

    // MARK: - Sidebar tab ↔ content tab sync

    /// Returns the sidebar tab that owns a given content tab type.
    private func sidebarOwner(of tab: ContentTab) -> SidebarTab {
        switch tab {
        case .terminal, .split: .sessions
        case .note: .notes
        case .file, .preview, .diff: .project
        }
    }

    /// Whether a content tab type belongs to the given sidebar context.
    func isTabAppropriate(_ tab: ContentTab, for sidebar: SidebarTab) -> Bool {
        switch sidebar {
        case .sessions: tab.isTerminal || tab.isSplit
        case .notes: tab.isNote
        case .project: tab.isProjectContent
        case .harness: tab.isProjectContent
        case .agents: false
        }
    }

    /// Called once at startup after tab restoration to ensure selectedContentTab
    /// is appropriate for the current sidebar. Reuses the per-sidebar restore logic.
    func ensureSelectedTabMatchesSidebar() {
        let sidebar = commandRouter.selectedSidebarTab
        if let tab = selectedContentTab, isTabAppropriate(tab, for: sidebar) { return }
        // Current tab doesn't match — run the restore for this sidebar.
        switch sidebar {
        case .sessions: restoreSessionsTab()
        case .notes: restoreNotesTab()
        case .project: restoreProjectTab()
        case .harness: restoreHarnessTab()
        case .agents: break
        }
    }

    /// Called when `selectedSidebarTab` changes.
    /// Saves the current content for the departing sidebar tab, then restores the last known
    /// content for the arriving tab. Each sidebar tab only saves/restores tabs that belong to it.
    func restoreContentTabOnSidebarSwitch(from oldTab: SidebarTab, to newTab: SidebarTab) {
        // Save under the departing tab only if the current tab naturally belongs to it,
        // or was explicitly tracked for it (e.g. harness-opened files via openProjectFile).
        // This prevents cross-contamination: a file tab opened while on sessions sidebar
        // (which auto-switches sidebar to project) must not overwrite the sessions memory.
        if let current = selectedContentTab {
            let owner = sidebarOwner(of: current)
            if owner == oldTab {
                lastContentTabBySidebarTab[oldTab] = current
            } else if lastContentTabBySidebarTab[oldTab]?.id == current.id {
                // Already explicitly tracked (e.g. harness file) — keep it fresh.
                lastContentTabBySidebarTab[oldTab] = current
            }
        }
        // Composer-triggered notes view is temporary — don't open a note tab in the right panel.
        if newTab == .notes, commandRouter.isComposerNotesActive { return }

        switch newTab {
        case .sessions:
            restoreSessionsTab()
        case .notes:
            restoreNotesTab()
        case .project:
            restoreProjectTab()
        case .harness:
            restoreHarnessTab()
        case .agents:
            break
        }
    }

    // MARK: - Per-sidebar restore

    /// Finds the live tab instance from openTabs or terminalItems matching the saved id.
    /// The saved copy in lastContentTabBySidebarTab may have stale titles; the live copy is authoritative.
    private func findLiveTab(matching saved: ContentTab) -> ContentTab? {
        tabManager.openTabs.first(where: { $0.id == saved.id })
            ?? tabManager.terminalItems.first(where: { $0.id == saved.id })
    }

    /// Sessions: restore the last terminal/split tab, or fall back to the active terminal.
    /// Sessions should never show empty state as long as at least one session exists.
    private func restoreSessionsTab() {
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
    private func restoreNotesTab() {
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

    /// Whether a file tab is a harness rule file (CLAUDE.md, AGENTS.md, etc.).
    private func isHarnessRuleFile(_ tab: ContentTab) -> Bool {
        guard let path = tab.filePath else { return false }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return AppConfig.Harness.supportedRuleFiles.contains(name)
    }

    /// Project: restore saved tab or empty state. Skips harness rule files.
    private func restoreProjectTab() {
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
    private func restoreHarnessTab() {
        if let saved = lastContentTabBySidebarTab[.harness],
           let live = findLiveTab(matching: saved) {
            selectAndActivate(live, for: .harness)
            return
        }
        sidebarShowsEmpty.insert(.harness)
    }

    /// Selects the tab, clears empty state, and activates the session if applicable.
    private func selectAndActivate(_ tab: ContentTab, for sidebar: SidebarTab) {
        sidebarShowsEmpty.remove(sidebar)
        tabManager.selectedContentTab = tab
        activateRestoredSession(tab)
    }

    /// Sync activeSessionID when restoring a terminal or split tab.
    private func activateRestoredSession(_ tab: ContentTab) {
        switch tab {
        case let .terminal(sid, _):
            sessionStore.activateSession(id: sid)
        case let .split(left, right, _, _):
            sessionStore.activateSession(id: tabManager.focusedSlot == .left ? left : right)
        default:
            break
        }
    }

    func restoreOpenTabs() {
        guard let data = UserDefaults.standard.data(forKey: tabsDefaultsKey) else { return }
        let restored: [ContentTab]
        do {
            restored = try JSONDecoder().decode([ContentTab].self, from: data)
        } catch {
            persistLogger.warning("Failed to decode open tabs: \(error.localizedDescription)")
            return
        }
        guard !restored.isEmpty else { return }
        for tab in restored {
            if let idx = tabManager.openTabs.firstIndex(where: { $0.id == tab.id }) {
                tabManager.openTabs[idx] = tab
            } else {
                tabManager.openTabs.append(tab)
            }
        }
        let selectedKey = AppConfig.UserDefaultsKeys.openTabsSelected(
            projectRoot: sessionStore.projectRoot ?? "default"
        )
        if let selectedID = UserDefaults.standard.string(forKey: selectedKey),
           let match = tabManager.terminalItems.first(where: { $0.id == selectedID }) ??
           tabManager.openTabs.first(where: { $0.id == selectedID }) {
            tabManager.selectedContentTab = match
        }
        // Restore per-sidebar memory from persisted state.
        let memoryKey = AppConfig.UserDefaultsKeys.sidebarTabMemory(
            projectRoot: sessionStore.projectRoot ?? "default"
        )
        if let memory = UserDefaults.standard.dictionary(forKey: memoryKey) as? [String: String] {
            for (sidebarRaw, tabID) in memory {
                guard let sidebar = SidebarTab(rawValue: sidebarRaw) else { continue }
                if let tab = tabManager.openTabs.first(where: { $0.id == tabID })
                    ?? tabManager.terminalItems.first(where: { $0.id == tabID }) {
                    lastContentTabBySidebarTab[sidebar] = tab
                }
            }
        }
        // Migration: if no persisted sidebar memory exists, seed from restored tabs
        // by natural owner type. Harness files are indistinguishable from project files
        // at this point, so they go under .project; harness gets correct tracking once
        // the user opens a file from the harness sidebar (synchronous tracking kicks in).
        // Fill any sidebar that has no saved tab from restored open tabs.
        for tab in tabManager.openTabs {
            if tab.isProjectContent, isHarnessRuleFile(tab) {
                if lastContentTabBySidebarTab[.harness] == nil {
                    lastContentTabBySidebarTab[.harness] = tab
                }
            } else {
                let owner = sidebarOwner(of: tab)
                if lastContentTabBySidebarTab[owner] == nil {
                    lastContentTabBySidebarTab[owner] = tab
                }
            }
        }
    }
}
