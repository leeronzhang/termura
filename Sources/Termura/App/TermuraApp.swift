import SwiftUI

@main
struct TermuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                themeManager: appDelegate.services.themeManager,
                fontSettings: appDelegate.services.fontSettings,
                themeImportService: appDelegate.services.themeImportService
            )
        }
        .commands {
            AppCommands()
        }
    }
}
