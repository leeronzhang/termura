import SwiftUI

/// Thin wrapper — bridges ProjectContext scopes into the SwiftUI environment.
/// Individual feature scopes replace the former monolithic @EnvironmentObject,
/// enforcing least-privilege: each view declares only the scopes it needs.
struct ContentView: View {
    let projectContext: ProjectContext
    let themeManager: ThemeManager
    let fontSettings: FontSettings

    var body: some View {
        MainView()
            .environment(\.sessionScope, projectContext.sessionScope)
            .environment(\.dataScope, projectContext.dataScope)
            .environment(\.projectScope, projectContext.projectScope)
            .environment(\.viewStateManager, projectContext.viewStateManager)
            .environment(\.commandRouter, projectContext.commandRouter)
            .environment(\.notesViewModel, projectContext.notesViewModel)
            .environment(\.themeManager, themeManager)
            .environment(\.fontSettings, fontSettings)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .ignoresSafeArea(edges: .top)
    }
}
