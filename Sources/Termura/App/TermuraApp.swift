import SwiftUI

@main
struct TermuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            ThemePickerView(
                themeManager: appDelegate.themeManager,
                themeImportService: appDelegate.themeImportService
            )
        }
        .commands {
            AppCommands()
        }
    }
}
