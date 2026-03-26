import SwiftUI

/// Thin wrapper — bridges ProjectContext into the SwiftUI environment.
/// ProjectContext remains @EnvironmentObject (no meaningful default possible).
/// ThemeManager, CommandRouter, NotesViewModel, FontSettings use type-safe @Environment keys.
struct ContentView: View {
    let projectContext: ProjectContext
    let themeManager: ThemeManager
    let fontSettings: FontSettings

    var body: some View {
        MainView()
            .environmentObject(projectContext)
            .environment(\.commandRouter, projectContext.commandRouter)
            .environment(\.notesViewModel, projectContext.notesViewModel)
            .environment(\.themeManager, themeManager)
            .environment(\.fontSettings, fontSettings)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .ignoresSafeArea(edges: .top)
    }
}
