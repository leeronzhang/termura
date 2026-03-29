import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectContext")

/// Per-project composition root. Each window owns exactly one `ProjectContext`
/// whose services are backed by `<projectURL>/.termura/termura.db`.
/// Not injected into views — feature-scoped containers (SessionScope, DataScope,
/// ProjectScope, SessionViewStateManager) are injected via @Environment instead.
@MainActor
final class ProjectContext {
    let projectURL: URL

    // MARK: - Core infrastructure

    let databaseService: any DatabaseServiceProtocol
    let engineStore: TerminalEngineStore

    // MARK: - Repositories

    let sessionRepository: any SessionRepositoryProtocol
    let noteRepository: any NoteRepositoryProtocol
    let sessionMessageRepository: any SessionMessageRepositoryProtocol
    let harnessEventRepository: any HarnessEventRepositoryProtocol
    let ruleFileRepository: any RuleFileRepositoryProtocol
    let sessionSnapshotRepository: any SessionSnapshotRepositoryProtocol

    // MARK: - Stores & services

    let sessionStore: SessionStore
    let agentStateStore: AgentStateStore
    let searchService: any SearchServiceProtocol
    let sessionArchiveService: SessionArchiveService
    let sessionHandoffService: any SessionHandoffServiceProtocol
    let contextInjectionService: any ContextInjectionServiceProtocol
    let experienceCodifier: ExperienceCodifier
    let gitService: any GitServiceProtocol
    let commandRouter: CommandRouter
    /// Global service — referenced per-project for environment injection.
    let tokenCountingService: any TokenCountingServiceProtocol
    /// Metrics collector — records counters, histograms, and gauges for observability.
    let metricsCollector: any MetricsCollectorProtocol
    /// Database health monitor — periodic SELECT 1 probe.
    let dbHealthMonitor: DBHealthMonitor
    /// Crash context — ring buffer + UserDefaults persistence.
    let crashContext: CrashContext
    /// Per-project notes ViewModel — created here so views can share it via @EnvironmentObject.
    let notesViewModel: NotesViewModel
    /// Per-project file tree ViewModel — owned here so expanded state survives
    /// sidebar re-evaluations. Views receive it as @ObservedObject.
    let projectViewModel: ProjectViewModel

    // MARK: - Feature scopes (injected into SwiftUI environment)

    let sessionScope: SessionScope
    let dataScope: DataScope
    let projectScope: ProjectScope
    let viewStateManager: SessionViewStateManager

    // MARK: - Init (private — use open(at:engineFactory:))

    /// Named struct ensures each of the 28 dependencies is assigned by label, preventing same-typed arg swaps.
    private struct Components {
        let projectURL: URL
        let databaseService: any DatabaseServiceProtocol
        let engineStore: TerminalEngineStore
        let sessionRepository: any SessionRepositoryProtocol
        let noteRepository: any NoteRepositoryProtocol
        let sessionMessageRepository: any SessionMessageRepositoryProtocol
        let harnessEventRepository: any HarnessEventRepositoryProtocol
        let ruleFileRepository: any RuleFileRepositoryProtocol
        let sessionSnapshotRepository: any SessionSnapshotRepositoryProtocol
        let sessionStore: SessionStore
        let agentStateStore: AgentStateStore
        let searchService: any SearchServiceProtocol
        let sessionArchiveService: SessionArchiveService
        let sessionHandoffService: any SessionHandoffServiceProtocol
        let contextInjectionService: any ContextInjectionServiceProtocol
        let experienceCodifier: ExperienceCodifier
        let gitService: any GitServiceProtocol
        let commandRouter: CommandRouter
        let tokenCountingService: any TokenCountingServiceProtocol
        let metricsCollector: any MetricsCollectorProtocol
        let dbHealthMonitor: DBHealthMonitor
        let crashContext: CrashContext
        let notesViewModel: NotesViewModel
        let projectViewModel: ProjectViewModel
        let sessionScope: SessionScope
        let dataScope: DataScope
        let projectScope: ProjectScope
        let viewStateManager: SessionViewStateManager
    }

    private init(_ components: Components) {
        projectURL = components.projectURL
        databaseService = components.databaseService
        engineStore = components.engineStore
        sessionRepository = components.sessionRepository
        noteRepository = components.noteRepository
        sessionMessageRepository = components.sessionMessageRepository
        harnessEventRepository = components.harnessEventRepository
        ruleFileRepository = components.ruleFileRepository
        sessionSnapshotRepository = components.sessionSnapshotRepository
        sessionStore = components.sessionStore
        agentStateStore = components.agentStateStore
        searchService = components.searchService
        sessionArchiveService = components.sessionArchiveService
        sessionHandoffService = components.sessionHandoffService
        contextInjectionService = components.contextInjectionService
        experienceCodifier = components.experienceCodifier
        gitService = components.gitService
        commandRouter = components.commandRouter
        tokenCountingService = components.tokenCountingService
        metricsCollector = components.metricsCollector
        dbHealthMonitor = components.dbHealthMonitor
        crashContext = components.crashContext
        notesViewModel = components.notesViewModel
        projectViewModel = components.projectViewModel
        sessionScope = components.sessionScope
        dataScope = components.dataScope
        projectScope = components.projectScope
        viewStateManager = components.viewStateManager
    }

    /// Project display name (directory basename).
    var displayName: String { projectURL.lastPathComponent }

    // MARK: - Factory

    /// Opens a project, creating `<projectURL>/.termura/termura.db` if needed.
    /// Async so that DB migration runs on the DatabaseService actor executor (off main thread).
    static func open(
        at projectURL: URL,
        engineFactory: any TerminalEngineFactory,
        tokenCountingService: any TokenCountingServiceProtocol,
        metricsCollector: (any MetricsCollectorProtocol)? = nil
    ) async throws -> ProjectContext {
        let fallbackMetrics: any MetricsCollectorProtocol = metricsCollector ?? MetricsCollector()
        let db = try await DatabaseService(
            pool: DatabaseService.makePool(at: projectURL), metrics: fallbackMetrics
        )
        let repos = makeRepositories(db: db)
        let services = makeServices(
            repos: repos, projectURL: projectURL,
            engineFactory: engineFactory, metricsCollector: fallbackMetrics
        )
        let healthMonitor = DBHealthMonitor(db: db, metrics: fallbackMetrics)
        let crashCtx = CrashContext(metrics: fallbackMetrics)
        Task { await healthMonitor.start() }

        // Lifecycle: one-shot housekeeping — gitignore management is non-critical.
        let url = projectURL
        Task.detached { ensureProjectGitignore(at: url) }
        logger.info("Opened project at \(projectURL.path)")
        let notesVM = NotesViewModel(repository: repos.note)
        let projectVM = ProjectViewModel(
            gitService: services.git,
            projectRoot: projectURL.path,
            commandRouter: services.router
        )
        let scopes = makeScopes(
            repos: repos, services: services,
            tokenCountingService: tokenCountingService,
            metricsCollector: fallbackMetrics,
            projectVM: projectVM
        )
        return ProjectContext(Components(
            projectURL: projectURL,
            databaseService: db,
            engineStore: services.engineStore,
            sessionRepository: repos.session,
            noteRepository: repos.note,
            sessionMessageRepository: repos.message,
            harnessEventRepository: repos.harness,
            ruleFileRepository: repos.rule,
            sessionSnapshotRepository: repos.snapshot,
            sessionStore: services.sessionStore,
            agentStateStore: services.agentState,
            searchService: services.search,
            sessionArchiveService: services.archive,
            sessionHandoffService: services.handoff,
            contextInjectionService: services.injection,
            experienceCodifier: services.codifier,
            gitService: services.git,
            commandRouter: services.router,
            tokenCountingService: tokenCountingService,
            metricsCollector: fallbackMetrics,
            dbHealthMonitor: healthMonitor,
            crashContext: crashCtx,
            notesViewModel: notesVM,
            projectViewModel: projectVM,
            sessionScope: scopes.session,
            dataScope: scopes.data,
            projectScope: scopes.project,
            viewStateManager: scopes.viewState
        ))
    }

    // MARK: - Factory helpers

    private struct ProjectRepositories {
        let session: any SessionRepositoryProtocol
        let note: any NoteRepositoryProtocol
        let message: any SessionMessageRepositoryProtocol
        let harness: any HarnessEventRepositoryProtocol
        let rule: any RuleFileRepositoryProtocol
        let snapshot: any SessionSnapshotRepositoryProtocol
    }

    private static func makeRepositories(db: any DatabaseServiceProtocol) -> ProjectRepositories {
        #if HARNESS_ENABLED
        let ruleRepo: any RuleFileRepositoryProtocol = RuleFileRepository(db: db)
        #else
        let ruleRepo: any RuleFileRepositoryProtocol = NullRuleFileRepository()
        #endif
        return ProjectRepositories(
            session: SessionRepository(db: db),
            note: NoteRepository(db: db),
            message: SessionMessageRepository(db: db),
            harness: HarnessEventRepository(db: db),
            rule: ruleRepo,
            snapshot: SessionSnapshotRepository(db: db)
        )
    }

    private struct ProjectServices {
        let engineStore: TerminalEngineStore
        let sessionStore: SessionStore
        let agentState: AgentStateStore
        let search: any SearchServiceProtocol
        let archive: SessionArchiveService
        let handoff: any SessionHandoffServiceProtocol
        let injection: any ContextInjectionServiceProtocol
        let codifier: ExperienceCodifier
        let git: any GitServiceProtocol
        let router: CommandRouter
    }

    private static func makeServices(
        repos: ProjectRepositories, projectURL: URL,
        engineFactory: any TerminalEngineFactory,
        metricsCollector: any MetricsCollectorProtocol
    ) -> ProjectServices {
        let eng = TerminalEngineStore(factory: engineFactory)
        let hoff = SessionHandoffService(
            messageRepo: repos.message, harnessEventRepo: repos.harness
        )
        return ProjectServices(
            engineStore: eng,
            sessionStore: SessionStore(
                engineStore: eng, projectRoot: projectURL.path,
                repository: repos.session, metricsCollector: metricsCollector
            ),
            agentState: AgentStateStore(),
            search: SearchService(
                sessionRepository: repos.session, noteRepository: repos.note,
                metrics: metricsCollector
            ),
            archive: SessionArchiveService(repository: repos.session),
            handoff: hoff,
            injection: ContextInjectionService(handoffService: hoff),
            codifier: ExperienceCodifier(harnessEventRepo: repos.harness),
            git: GitService(), router: CommandRouter()
        )
    }

    private struct ProjectScopes {
        let session: SessionScope
        let data: DataScope
        let project: ProjectScope
        let viewState: SessionViewStateManager
    }

    private static func makeScopes(
        repos: ProjectRepositories,
        services: ProjectServices,
        tokenCountingService: any TokenCountingServiceProtocol,
        metricsCollector: any MetricsCollectorProtocol,
        projectVM: ProjectViewModel
    ) -> ProjectScopes {
        let session = SessionScope(
            store: services.sessionStore, engines: services.engineStore, agentStates: services.agentState
        )
        let data = DataScope(
            searchService: services.search, vectorSearchService: nil,
            ruleFileRepository: repos.rule, sessionMessageRepository: repos.message
        )
        let viewState = SessionViewStateManager(
            commandRouter: services.router, sessionStore: services.sessionStore,
            tokenCountingService: tokenCountingService, agentStateStore: services.agentState,
            contextInjectionService: services.injection, sessionHandoffService: services.handoff,
            metricsCollector: metricsCollector
        )
        return ProjectScopes(
            session: session, data: data,
            project: ProjectScope(gitService: services.git, viewModel: projectVM),
            viewState: viewState
        )
    }
}
