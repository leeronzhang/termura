import SwiftUI

@main
struct TermuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                themeManager: appDelegate.themeManager,
                fontSettings: appDelegate.fontSettings,
                themeImportService: appDelegate.themeImportService
            )
        }
        .commands {
            AppCommands()
        }
    }
}
