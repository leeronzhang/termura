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

    // MARK: - Menu Bar

    func setupMenuBarActivation() {
        services.menuBarService.configure { [weak self] in
            self?.bringMainWindowToFront()
        }
    }

    func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
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
