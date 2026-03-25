import SwiftUI

/// Thin wrapper — bridges ProjectContext into MainView.
struct ContentView: View {
    @ObservedObject var projectContext: ProjectContext
    let themeManager: ThemeManager
    let tokenCountingService: TokenCountingService

    init(
        projectContext: ProjectContext,
        themeManager: ThemeManager,
        tokenCountingService: TokenCountingService
    ) {
        self.projectContext = projectContext
        self.themeManager = themeManager
        self.tokenCountingService = tokenCountingService
    }

    var body: some View {
        MainView(
            sessionStore: projectContext.sessionStore,
            engineStore: projectContext.engineStore,
            themeManager: themeManager,
            tokenCountingService: tokenCountingService,
            searchService: projectContext.searchService,
            noteRepository: projectContext.noteRepository,
            agentStateStore: projectContext.agentStateStore,
            contextInjectionService: projectContext.contextInjectionService,
            gitService: projectContext.gitService,
            vectorSearchService: projectContext.vectorSearchService,
            sessionMessageRepository: projectContext.sessionMessageRepository,
            ruleFileRepository: projectContext.ruleFileRepository,
            sessionHandoffService: projectContext.sessionHandoffService
        )
        .toolbarBackground(.hidden, for: .windowToolbar)
        .ignoresSafeArea(edges: .top)
    }
}
