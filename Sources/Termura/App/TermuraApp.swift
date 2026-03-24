import SwiftUI

@main
struct TermuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(
                tokenCountingService: appDelegate.tokenCountingService,
                searchService: appDelegate.searchService,
                noteRepository: appDelegate.noteRepository,
                agentStateStore: appDelegate.agentStateStore,
                contextInjectionService: appDelegate.contextInjectionService
            )
            .environmentObject(appDelegate.sessionStore)
            .environmentObject(appDelegate.engineStore)
            .environmentObject(appDelegate.themeManager)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
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
