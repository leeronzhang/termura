import SwiftUI

/// Thin wrapper — injects environment into MainView.
struct ContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var engineStore: TerminalEngineStore
    @EnvironmentObject private var themeManager: ThemeManager
    /// Passed via direct injection since TokenCountingService is an actor (not ObservableObject).
    let tokenCountingService: TokenCountingService
    let searchService: SearchService
    let noteRepository: any NoteRepositoryProtocol

    var body: some View {
        MainView(
            sessionStore: sessionStore,
            engineStore: engineStore,
            themeManager: themeManager,
            tokenCountingService: tokenCountingService,
            searchService: searchService,
            noteRepository: noteRepository
        )
    }
}
