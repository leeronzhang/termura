import SwiftUI

@main
struct TermuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(
                tokenCountingService: appDelegate.tokenCountingService,
                searchService: appDelegate.searchService,
                noteRepository: appDelegate.noteRepository
            )
            .environmentObject(appDelegate.sessionStore)
            .environmentObject(appDelegate.engineStore)
            .environmentObject(appDelegate.themeManager)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands()
        }

        Settings {
            ThemePickerView(
                themeManager: appDelegate.themeManager,
                themeImportService: appDelegate.themeImportService
            )
        }
    }
}
