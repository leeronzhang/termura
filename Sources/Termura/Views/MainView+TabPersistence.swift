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
            case .note, .noteSplit, .file, .preview: true
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
        userDefaults.set(data, forKey: tabsDefaultsKey)
        if let tab = selectedContentTab {
            let selectedKey = AppConfig.UserDefaultsKeys.openTabsSelected(
                projectRoot: sessionStore.projectRoot ?? "default"
            )
            userDefaults.set(tab.id, forKey: selectedKey)
        }
        // Persist per-sidebar tab memory so sidebar restore works across launches.
        let memoryKey = AppConfig.UserDefaultsKeys.sidebarTabMemory(
            projectRoot: sessionStore.projectRoot ?? "default"
        )
        let sidebarMemory: [String: String] = lastContentTabBySidebarTab.reduce(into: [:]) { result, pair in
            result[pair.key.rawValue] = pair.value.id
        }
        userDefaults.set(sidebarMemory, forKey: memoryKey)
    }

    // MARK: - Sidebar tab ↔ content tab sync

    /// Returns the sidebar tab that owns a given content tab type.
    private func sidebarOwner(of tab: ContentTab) -> SidebarTab {
        switch tab {
        case .terminal, .split: .sessions
        case .note, .noteSplit: .notes
        case .file, .preview, .diff: .project
        }
    }

    /// Whether a content tab type belongs to the given sidebar context.
    func isTabAppropriate(_ tab: ContentTab, for sidebar: SidebarTab) -> Bool {
        switch sidebar {
        case .sessions: tab.isTerminal || tab.isSplit
        case .knowledge: tab.isNote
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
        case .knowledge: restoreNotesTab()
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
        case .knowledge:
            restoreNotesTab()
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

    // MARK: - Helpers

    /// Finds the live tab instance from openTabs or terminalItems matching the saved id.
    /// The saved copy in lastContentTabBySidebarTab may have stale titles; the live copy is authoritative.
    func findLiveTab(matching saved: ContentTab) -> ContentTab? {
        tabManager.openTabs.first(where: { $0.id == saved.id })
            ?? tabManager.terminalItems.first(where: { $0.id == saved.id })
    }

    /// Whether a file tab is a harness rule file (CLAUDE.md, AGENTS.md, etc.).
    func isHarnessRuleFile(_ tab: ContentTab) -> Bool {
        guard let path = tab.filePath else { return false }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return AppConfig.Harness.supportedRuleFiles.contains(name)
    }

    func restoreOpenTabs() {
        guard let data = userDefaults.data(forKey: tabsDefaultsKey) else { return }
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
        if let selectedID = userDefaults.string(forKey: selectedKey),
           let match = tabManager.terminalItems.first(where: { $0.id == selectedID }) ??
           tabManager.openTabs.first(where: { $0.id == selectedID }) {
            tabManager.selectedContentTab = match
        }
        // Restore per-sidebar memory from persisted state.
        let memoryKey = AppConfig.UserDefaultsKeys.sidebarTabMemory(
            projectRoot: sessionStore.projectRoot ?? "default"
        )
        if let memory = userDefaults.dictionary(forKey: memoryKey) as? [String: String] {
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
