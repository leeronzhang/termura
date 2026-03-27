import Foundation

// Feature-scoped DI containers. Each scope groups related services
// so views declare only the dependencies they actually use.
// ProjectContext remains the composition root that creates these scopes;
// scopes are injected into the SwiftUI environment, not ProjectContext itself.

// MARK: - SessionScope

/// Core session lifecycle: store, terminal engines, agent state.
/// Used by views that display or manage sessions.
@MainActor
final class SessionScope {
    let store: SessionStore
    let engines: TerminalEngineStore
    let agentStates: AgentStateStore

    init(
        store: SessionStore,
        engines: TerminalEngineStore,
        agentStates: AgentStateStore
    ) {
        self.store = store
        self.engines = engines
        self.agentStates = agentStates
    }
}

// MARK: - DataScope

/// Data-access services: repositories and search.
/// Used by views that query or display persisted data (sheets, harness, etc.).
@MainActor
final class DataScope {
    let searchService: any SearchServiceProtocol
    let vectorSearchService: any VectorSearchServiceProtocol
    let ruleFileRepository: any RuleFileRepositoryProtocol
    let sessionMessageRepository: any SessionMessageRepositoryProtocol

    init(
        searchService: any SearchServiceProtocol,
        vectorSearchService: any VectorSearchServiceProtocol,
        ruleFileRepository: any RuleFileRepositoryProtocol,
        sessionMessageRepository: any SessionMessageRepositoryProtocol
    ) {
        self.searchService = searchService
        self.vectorSearchService = vectorSearchService
        self.ruleFileRepository = ruleFileRepository
        self.sessionMessageRepository = sessionMessageRepository
    }
}

// MARK: - ProjectScope

/// Git and project file-tree services.
/// Used by views that display project structure or diffs.
@MainActor
final class ProjectScope {
    let gitService: any GitServiceProtocol
    let viewModel: ProjectViewModel

    init(gitService: any GitServiceProtocol, viewModel: ProjectViewModel) {
        self.gitService = gitService
        self.viewModel = viewModel
    }
}

// MARK: - SessionViewStateManager

/// Owns the per-session view-state cache (OutputStore, TerminalViewModel, etc.).
/// Extracted from ProjectContext so the cache + factory logic lives in a focused type.
@MainActor
final class SessionViewStateManager {
    private(set) var sessionViewStates: [SessionID: SessionViewState] = [:]
    private(set) var outputStores: [SessionID: OutputStore] = [:]

    // Factory dependencies (captured at init, invisible to views).
    private let commandRouter: CommandRouter
    private let sessionStore: SessionStore
    private let tokenCountingService: any TokenCountingServiceProtocol
    private let agentStateStore: AgentStateStore
    private let contextInjectionService: any ContextInjectionServiceProtocol
    private let sessionHandoffService: any SessionHandoffServiceProtocol

    init(
        commandRouter: CommandRouter,
        sessionStore: SessionStore,
        tokenCountingService: any TokenCountingServiceProtocol,
        agentStateStore: AgentStateStore,
        contextInjectionService: any ContextInjectionServiceProtocol,
        sessionHandoffService: any SessionHandoffServiceProtocol
    ) {
        self.commandRouter = commandRouter
        self.sessionStore = sessionStore
        self.tokenCountingService = tokenCountingService
        self.agentStateStore = agentStateStore
        self.contextInjectionService = contextInjectionService
        self.sessionHandoffService = sessionHandoffService
    }

    /// Returns (or lazily creates) the per-session view state for the given session.
    func viewState(
        for sessionID: SessionID,
        engine: any TerminalEngine
    ) -> SessionViewState {
        if let existing = sessionViewStates[sessionID] { return existing }

        let outputStore = OutputStore(sessionID: sessionID, commandRouter: commandRouter)
        let modeCtrl = InputModeController()
        let timeline = SessionTimeline()
        let vm = TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            outputStore: outputStore,
            tokenCountingService: tokenCountingService,
            modeController: modeCtrl,
            agentStateStore: agentStateStore,
            isRestoredSession: sessionStore.isRestoredSession(id: sessionID),
            contextInjectionService: contextInjectionService,
            sessionHandoffService: sessionHandoffService
        )
        let editorVM = EditorViewModel(engine: engine, modeController: modeCtrl)

        let state = SessionViewState(
            outputStore: outputStore,
            viewModel: vm,
            editorViewModel: editorVM,
            modeController: modeCtrl,
            timeline: timeline
        )
        sessionViewStates[sessionID] = state
        outputStores[sessionID] = outputStore
        return state
    }

    /// Remove cached view state when a session is closed.
    func removeViewState(for sessionID: SessionID) {
        sessionViewStates[sessionID] = nil
        outputStores[sessionID] = nil
    }

    // MARK: - OutputStore registry

    func registerOutputStore(_ store: OutputStore, for sessionID: SessionID) {
        outputStores[sessionID] = store
    }

    func unregisterOutputStore(for sessionID: SessionID) {
        outputStores[sessionID] = nil
    }

    func clearAll() {
        sessionViewStates.removeAll()
        outputStores.removeAll()
    }
}
