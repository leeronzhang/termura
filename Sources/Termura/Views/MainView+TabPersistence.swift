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

    /// Called whenever `selectedContentTab` changes — keeps the per-sidebar-tab memory current.
    /// Saves under the content tab's natural owner, and also under the current sidebar tab
    /// when they differ (e.g. a rule file opened from the Harness sidebar has sidebarOwner
    /// `.project` but should also be tracked under `.harness`).
    func trackContentTabForSidebarTab(_ tab: ContentTab) {
        let owner = sidebarOwner(of: tab)
        lastContentTabBySidebarTab[owner] = tab
        let currentSidebar = commandRouter.selectedSidebarTab
        if currentSidebar != owner {
            lastContentTabBySidebarTab[currentSidebar] = tab
        }
    }

    /// Called when `selectedSidebarTab` changes.
    /// Saves the current content for the departing sidebar tab, then restores the last known
    /// content for the arriving tab. All sidebar tabs participate in the save/restore cycle.
    func restoreContentTabOnSidebarSwitch(from oldTab: SidebarTab, to newTab: SidebarTab) {
        // Always save under the departing tab — not gated by sidebarOwner — so that
        // e.g. a harness-opened file is remembered when switching away from harness.
        if let current = selectedContentTab {
            lastContentTabBySidebarTab[oldTab] = current
        }
        // Composer-triggered notes view is temporary — don't open a note tab in the right panel.
        if newTab == .notes, commandRouter.isComposerNotesActive { return }
        guard let last = lastContentTabBySidebarTab[newTab],
              tabManager.openTabs.contains(last) || tabManager.terminalItems.contains(last) else {
            // No restorable content for this sidebar tab — mark it for empty state display.
            // Cleared by onSelectedContentTabChange when the user explicitly selects a tab.
            sidebarShowsEmpty.insert(newTab)
            return
        }
        sidebarShowsEmpty.remove(newTab)
        tabManager.selectedContentTab = last
        switch last {
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
        for tab in restored where !tabManager.openTabs.contains(tab) {
            tabManager.openTabs.append(tab)
        }
        let selectedKey = AppConfig.UserDefaultsKeys.openTabsSelected(
            projectRoot: sessionStore.projectRoot ?? "default"
        )
        if let selectedID = UserDefaults.standard.string(forKey: selectedKey),
           let match = tabManager.terminalItems.first(where: { $0.id == selectedID }) ??
           tabManager.openTabs.first(where: { $0.id == selectedID }) {
            tabManager.selectedContentTab = match
        }
    }
}
