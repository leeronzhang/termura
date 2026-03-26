import AppKit
import KeyboardShortcuts
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AppDelegate+Helpers")

extension AppDelegate {

    // MARK: - Shell Integration Onboarding

    func checkShellIntegrationOnboarding() {
        let installed = UserDefaults.standard.bool(
            forKey: AppConfig.ShellIntegration.installedDefaultsKey
        )
        if !installed {
            showShellOnboarding = true
        }
    }

    // MARK: - Persistence

    func persistOpenProjects() {
        let paths = projectWindows.keys.map(\.path)
        UserDefaults.standard.set(paths, forKey: "openProjectPaths")
    }

    func openLastProjectOrShowPicker() {
        Task { @MainActor in
            await ProjectMigrationService.migrateIfNeeded()
            if let lastURL = recentProjects.lastOpened() {
                openProject(at: lastURL)
            } else {
                showProjectPicker()
            }
        }
    }

    // MARK: - Window Focus

    func observeWindowFocus() {
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for (_, controller) in projectWindows where controller.window === window {
                    activeContext = controller.projectContext
                    return
                }
            }
        }
    }

    // MARK: - Menu Bar

    func setupMenuBarActivation() {
        menuBarService.configure { [weak self] in
            self?.bringMainWindowToFront()
        }
    }

    func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
    }

    func setupChunkHandler(for context: ProjectContext) {
        context.commandRouter.onChunkCompleted { [weak self] chunk in
            guard let self else { return }
            if let code = chunk.exitCode, code != 0 {
                menuBarService.recordFailure()
            }
            let service = notificationService
            Task { await service.notifyIfLong(chunk) }
        }
    }

    // MARK: - Visor

    func setupVisorShortcut() {
        KeyboardShortcuts.setShortcut(
            .init(.backtick, modifiers: .command),
            for: .toggleVisor
        )
        KeyboardShortcuts.onKeyUp(for: .toggleVisor) { [weak self] in
            self?.toggleVisor()
        }
    }
}
