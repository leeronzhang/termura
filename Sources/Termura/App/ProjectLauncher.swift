import AppKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectLauncher")

/// Handles project discovery and initiation UI (Welcome window, picker,
/// restoration, open-on-launch URLs). Delegates actual window creation
/// to ProjectCoordinator.
@MainActor
final class ProjectLauncher {
    struct Dependencies {
        let appServices: AppServices
        let userDefaults: any UserDefaultsStoring
        var openOnLaunchURL: URL?
    }

    private let deps: Dependencies
    private weak var coordinator: ProjectCoordinator?
    /// Strong ref to the Welcome window controller while it is on
    /// screen. Cleared after the user picks a project or dismisses the
    /// window so AppKit can deallocate the controller + hosting view.
    private var welcomeController: WelcomeWindowController?

    init(dependencies: Dependencies, coordinator: ProjectCoordinator) {
        deps = dependencies
        self.coordinator = coordinator
    }

    // MARK: - Cold launch (app start)

    /// Cold-launch entry. Consults the user's "Show Welcome on launch"
    /// preference: when on (default), surfaces the Welcome window so
    /// first-launch users have a discoverable affordance; when off,
    /// silently restores the last project (or shows the open panel if
    /// there is none) — the pre-Welcome behaviour.
    func coldLaunch() {
        Task {
            await ProjectMigrationService.migrateIfNeeded()
            // openOnLaunchURL (UI tests / URL-scheme deep links): open without persisting to recents.
            if let override = deps.openOnLaunchURL {
                coordinator?.openProject(at: override, persist: false)
                return
            }
            if shouldShowWelcome {
                presentWelcomeWindow()
            } else {
                openLastOrShowPicker()
            }
        }
    }

    /// Reopen entry (Dock click / `applicationShouldHandleReopen`).
    /// Never surfaces the Welcome window — macOS reopen semantics are
    /// "restore what was there", and a modal-feeling Welcome would
    /// interrupt the user's mental model.
    func restoreLastProjectOrShowPicker() {
        Task {
            await ProjectMigrationService.migrateIfNeeded()
            if let override = deps.openOnLaunchURL {
                coordinator?.openProject(at: override, persist: false)
                return
            }
            openLastOrShowPicker()
        }
    }

    private func openLastOrShowPicker() {
        if let lastURL = deps.appServices.recentProjects.lastOpened() {
            coordinator?.openProject(at: lastURL)
        } else {
            showProjectPicker()
        }
    }

    // MARK: - Project picker (NSOpenPanel)

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

    /// Menu / Dock "New Project…" entry point. Mirrors `showProjectPicker`'s
    /// window handling (sheet on the key window, else modal) but uses an
    /// `NSSavePanel` to name+place a new directory, then opens it as a project.
    /// Reachable without the Welcome window (e.g. Dock right-click with no open
    /// window), unlike `handleWelcomeCreateNew`.
    func showNewProjectPanel() {
        let panel = makeNewProjectSavePanel()
        NSApp.activate(ignoringOtherApps: true)
        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.createProjectDirectory(at: url, parent: keyWindow)
            }
        } else {
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                createProjectDirectory(at: url, parent: nil)
            }
        }
    }

    private func makeNewProjectSavePanel() -> NSSavePanel {
        let panel = NSSavePanel()
        panel.title = String(localized: "Create New Project")
        panel.prompt = String(localized: "Create")
        panel.message = String(localized: "Choose a location and name for your new project.")
        panel.nameFieldLabel = String(localized: "Project name:")
        panel.nameFieldStringValue = String(localized: "Untitled Project")
        panel.canCreateDirectories = true
        return panel
    }

    // MARK: - Welcome window

    private var shouldShowWelcome: Bool {
        if deps.userDefaults.object(forKey: AppConfig.UserDefaultsKeys.welcomeShowAtStartup) == nil {
            return true
        }
        return deps.userDefaults.bool(forKey: AppConfig.UserDefaultsKeys.welcomeShowAtStartup)
    }

    private func presentWelcomeWindow() {
        let viewModel = WelcomeViewModel(recentProjects: deps.appServices.recentProjects,
                                         userDefaults: deps.userDefaults,
                                         appVersion: Self.resolveAppVersion(),
                                         actions: makeWelcomeActions())
        let controller = WelcomeWindowController(viewModel: viewModel)
        welcomeController = controller
        controller.present()
    }

    private static func resolveAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func makeWelcomeActions() -> WelcomeViewModel.Actions {
        WelcomeViewModel.Actions(openRecent: { [weak self] url in
                                     self?.handleWelcomeOpen(url: url)
                                 },
                                 createNewProject: { [weak self] in
                                     self?.handleWelcomeCreateNew()
                                 },
                                 openExistingProject: { [weak self] in
                                     self?.handleWelcomeOpenExisting()
                                 },
                                 dismissRequested: { [weak self] in
                                     self?.welcomeController = nil
                                 })
    }

    private func handleWelcomeOpen(url: URL) {
        welcomeController?.dismissAfterFlow()
        welcomeController = nil
        coordinator?.openProject(at: url)
    }

    private func handleWelcomeCreateNew() {
        guard let parentWindow = welcomeController?.window else { return }
        let panel = makeNewProjectSavePanel()
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.createProjectDirectory(at: url, parent: parentWindow)
        }
    }

    private func handleWelcomeOpenExisting() {
        guard let parentWindow = welcomeController?.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Open Project")
        panel.message = String(localized: "Choose a project directory to open in Termura")
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.handleWelcomeOpen(url: url)
        }
    }

    /// Materialises a fresh project directory then routes through
    /// `coordinator.openProject(at:)`, which lazily creates the
    /// `.termura/` data directory and persists the project to recents.
    /// `parent` is `nil` for the menu/Dock path when no window is key; the
    /// failure alert then falls back to a modal run.
    private func createProjectDirectory(at url: URL, parent: NSWindow?) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            let path = url.path
            let message = error.localizedDescription
            logger.error(
                "Failed to create project directory at \(path, privacy: .private): \(message, privacy: .private)"
            )
            presentCreateFailureAlert(error: error, parent: parent)
            return
        }
        handleWelcomeOpen(url: url)
    }

    private func presentCreateFailureAlert(error: any Error, parent: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Could not create project")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        if let parent {
            alert.beginSheetModal(for: parent)
        } else {
            alert.runModal()
        }
    }
}
