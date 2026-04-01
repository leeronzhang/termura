import SwiftUI

#if DEBUG

// MARK: - Preview factory

/// Builds a self-contained SessionViewState wired to mock dependencies.
/// Only used in Xcode Previews — never reached in production.
@MainActor
private func makePreviewViewState() -> SessionViewState {
    let sessionID = SessionID()
    let engine = MockTerminalEngine()
    let agentStateStore = MockAgentStateStore()
    let sessionStore = SessionStore(
        engineStore: TerminalEngineStore(factory: MockTerminalEngineFactory()),
        repository: MockSessionRepository()
    )
    let tokenService = MockTokenCountingService()
    let outputStore = OutputStore(sessionID: sessionID)
    let modeController = InputModeController()
    let agentCoordinator = AgentCoordinator(
        sessionID: sessionID,
        sessionStore: sessionStore,
        agentStateStore: agentStateStore
    )
    let outputProcessor = OutputProcessor(
        sessionID: sessionID,
        outputStore: outputStore,
        tokenCountingService: tokenService
    )
    let viewModel = TerminalViewModel(.init(
        sessionID: sessionID,
        engine: engine,
        sessionStore: sessionStore,
        modeController: modeController,
        agentCoordinator: agentCoordinator,
        outputProcessor: outputProcessor,
        sessionServices: SessionServices()
    ))
    let editorViewModel = EditorViewModel(engine: engine, modeController: modeController)
    return SessionViewState(
        outputStore: outputStore,
        viewModel: viewModel,
        editorViewModel: editorViewModel,
        modeController: modeController,
        timeline: SessionTimeline()
    )
}

// MARK: - Preview shell

/// Owns SessionViewState as @State so SwiftUI lifecycle is correctly observed.
private struct TerminalAreaPreviewShell: View {
    @State private var state = makePreviewViewState()

    var body: some View {
        TerminalAreaView(
            engine: state.viewModel.engine,
            sessionID: state.viewModel.sessionID,
            state: state
        )
    }
}

// MARK: - Previews

#Preview("Terminal Area") {
    TerminalAreaPreviewShell()
        .frame(width: 900, height: 600)
}

#Preview("Terminal Area \u{2014} Compact (split pane)") {
    TerminalAreaPreviewShell()
        .frame(width: 600, height: 400)
}

#endif
