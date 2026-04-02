import AppKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectLauncher")

/// Handles project discovery and initiation UI (picker, restoration, and open-on-launch URLs).
/// Delegates actual window creation to ProjectCoordinator.
@MainActor
final class ProjectLauncher {
    struct Dependencies {
        let appServices: AppServices
        let userDefaults: any UserDefaultsStoring
        var openOnLaunchURL: URL?
    }

    private let deps: Dependencies
    private weak var coordinator: ProjectCoordinator?

    init(dependencies: Dependencies, coordinator: ProjectCoordinator) {
        deps = dependencies
        self.coordinator = coordinator
    }

    /// Restore the most recently opened project or show the picker.
    /// Called on launch and on Dock icon click.
    func restoreLastProjectOrShowPicker() {
        Task {
            await ProjectMigrationService.migrateIfNeeded()

            // openOnLaunchURL (UI tests / URL-scheme deep links): open without persisting to recents.
            if let override = deps.openOnLaunchURL {
                coordinator?.openProject(at: override, persist: false)
                return
            }

            if let lastURL = deps.appServices.recentProjects.lastOpened() {
                coordinator?.openProject(at: lastURL)
            } else {
                showProjectPicker()
            }
        }
    }

    func showProjectPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Open Project")
        panel.message = String(localized: "Choose a project directory to open in Termura")

        NSApp.activate(ignoringOtherApps: true)

        if let keyWindow = NSApp.keyWindow {
            // Attach as a sheet so the panel is always visible above the current window.
            panel.beginSheetModal(for: keyWindow) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.coordinator?.openProject(at: url)
            }
        } else {
            // No key window (e.g. first launch, all windows closed).
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                coordinator?.openProject(at: url)
            }
        }
    }
}
