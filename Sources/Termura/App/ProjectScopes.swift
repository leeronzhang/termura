import Combine
import Foundation
import Observation

// Feature-scoped DI containers. Each scope groups related services
// so views declare only the dependencies they actually use.
// ProjectContext remains the composition root that creates these scopes;
// scopes are injected into the SwiftUI environment, not ProjectContext itself.

// MARK: - SessionScope

/// Core session lifecycle: store, terminal engines, agent state.
/// Used by views that display or manage sessions.
@Observable
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
@Observable
@MainActor
final class DataScope {
    let searchService: any SearchServiceProtocol
    /// Semantic vector search service. `nil` until a real Core ML embedding model is bundled;
    /// when nil the "Semantic" tab is hidden from the search UI.
    let vectorSearchService: (any VectorSearchServiceProtocol)?
    let ruleFileRepository: any RuleFileRepositoryProtocol
    let sessionMessageRepository: any SessionMessageRepositoryProtocol

    init(
        searchService: any SearchServiceProtocol,
        vectorSearchService: (any VectorSearchServiceProtocol)?,
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
@Observable
@MainActor
final class ProjectScope {
    let gitService: any GitServiceProtocol
    let viewModel: ProjectViewModel
    let diagnosticsStore: DiagnosticsStore

    init(
        gitService: any GitServiceProtocol,
        viewModel: ProjectViewModel,
        diagnosticsStore: DiagnosticsStore
    ) {
        self.gitService = gitService
        self.viewModel = viewModel
        self.diagnosticsStore = diagnosticsStore
    }
}

// MARK: - SessionViewStateManager

/// Owns the per-session view-state cache (OutputStore, TerminalViewModel, etc.).
/// Extracted from ProjectContext so the cache + factory logic lives in a focused type.
@Observable
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
    private let metricsCollector: (any MetricsCollectorProtocol)?
    private let notificationService: (any NotificationServiceProtocol)?
    // @ObservationIgnored: internal Combine subscription state; views must never
    // observe cancellables directly — mutation here must not trigger SwiftUI re-renders.
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    /// Groups the 7 factory dependencies. Required per CLAUDE.md §5:
    /// init with more than 6 parameters must pack them into a named struct.
    struct Components {
        let commandRouter: CommandRouter
        let sessionStore: SessionStore
        let tokenCountingService: any TokenCountingServiceProtocol
        let agentStateStore: AgentStateStore
        let contextInjectionService: any ContextInjectionServiceProtocol
        let sessionHandoffService: any SessionHandoffServiceProtocol
        let metricsCollector: (any MetricsCollectorProtocol)?
        let notificationService: (any NotificationServiceProtocol)? // Optional: observability, nil = no-op

        init(
            commandRouter: CommandRouter,
            sessionStore: SessionStore,
            tokenCountingService: any TokenCountingServiceProtocol,
            agentStateStore: AgentStateStore,
            contextInjectionService: any ContextInjectionServiceProtocol,
            sessionHandoffService: any SessionHandoffServiceProtocol,
            metricsCollector: (any MetricsCollectorProtocol)? = nil, // Optional: observability, nil = no-op
            notificationService: (any NotificationServiceProtocol)? = nil // Optional: observability, nil = no-op
        ) {
            self.commandRouter = commandRouter
            self.sessionStore = sessionStore
            self.tokenCountingService = tokenCountingService
            self.agentStateStore = agentStateStore
            self.contextInjectionService = contextInjectionService
            self.sessionHandoffService = sessionHandoffService
            self.metricsCollector = metricsCollector
            self.notificationService = notificationService
        }
    }

    init(_ components: Components) {
        self.commandRouter = components.commandRouter
        self.sessionStore = components.sessionStore
        self.tokenCountingService = components.tokenCountingService
        self.agentStateStore = components.agentStateStore
        self.contextInjectionService = components.contextInjectionService
        self.sessionHandoffService = components.sessionHandoffService
        self.metricsCollector = components.metricsCollector
        self.notificationService = components.notificationService

        sessionStore.sessionDidClose
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                guard let self else { return }
                removeViewState(for: id)
                self.agentStateStore.remove(sessionID: id)
                // Release per-session token accumulation data from the shared actor.
                // Must be done here — TokenCountingService is a shared project-level
                // actor, so its session entries are NOT freed by SessionViewState dealloc.
                let service = self.tokenCountingService
                Task { await service.reset(for: id) }
            }
            .store(in: &cancellables)
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
        let coordinator = makeAgentCoordinator(for: sessionID)
        let processor = makeOutputProcessor(sessionID: sessionID, outputStore: outputStore)
        let services = makeSessionServices(for: sessionID)

        let initialDir = sessionStore.session(id: sessionID)?.workingDirectory
            ?? AppConfig.Paths.homeDirectory
        let vm = TerminalViewModel(TerminalViewModel.Components(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: modeCtrl,
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: services,
            initialWorkingDirectory: initialDir,
            notificationService: notificationService
        ))
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

    private func makeAgentCoordinator(for sessionID: SessionID) -> AgentCoordinator {
        AgentCoordinator(
            sessionID: sessionID,
            sessionStore: sessionStore,
            agentStateStore: agentStateStore,
            metricsCollector: metricsCollector
        )
    }

    private func makeOutputProcessor(sessionID: SessionID, outputStore: OutputStore) -> OutputProcessor {
        OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: tokenCountingService
        )
    }

    private func makeSessionServices(for sessionID: SessionID) -> SessionServices {
        SessionServices(
            contextInjectionService: contextInjectionService,
            sessionHandoffService: sessionHandoffService,
            isRestoredSession: sessionStore.isRestoredSession(id: sessionID)
        )
    }

    /// Remove cached view state when a session is closed.
    /// Clears attachments first to ensure any temporary image files are deleted.
    func removeViewState(for sessionID: SessionID) {
        sessionViewStates[sessionID]?.editorViewModel.clearAttachments()
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
        agentStateStore.clearAll()
    }
}
