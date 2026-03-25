import SwiftUI

/// Thin wrapper — bridges ProjectContext into the SwiftUI environment.
/// All child views access services via `@EnvironmentObject var projectContext`.
struct ContentView: View {
    let projectContext: ProjectContext
    let themeManager: ThemeManager
    let fontSettings: FontSettings

    var body: some View {
        MainView()
            .environmentObject(projectContext)
            .environmentObject(projectContext.commandRouter)
            .environmentObject(projectContext.notesViewModel)
            .environmentObject(themeManager)
            .environmentObject(fontSettings)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .ignoresSafeArea(edges: .top)
    }
}
