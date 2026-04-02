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
    func trackContentTabForSidebarTab(_ tab: ContentTab) {
        lastContentTabBySidebarTab[sidebarOwner(of: tab)] = tab
    }

    /// Called when `selectedSidebarTab` changes.
    /// Saves the current content for the old sidebar tab, then restores the last known content
    /// for the new one (Sessions, Notes, Project only — Agents and Harness have no content tabs).
    func restoreContentTabOnSidebarSwitch(from oldTab: SidebarTab, to newTab: SidebarTab) {
        if let current = selectedContentTab, sidebarOwner(of: current) == oldTab {
            lastContentTabBySidebarTab[oldTab] = current
        }
        // Composer-triggered notes view is temporary — don't open a note tab in the right panel.
        if newTab == .notes && commandRouter.isComposerNotesActive { return }
        guard newTab == .sessions || newTab == .notes || newTab == .project else { return }
        guard let last = lastContentTabBySidebarTab[newTab],
              tabManager.openTabs.contains(last) || tabManager.terminalItems.contains(last) else { return }
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
