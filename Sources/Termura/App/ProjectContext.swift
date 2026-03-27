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
    let branchSummarizer: BranchSummarizer
    let embeddingService: EmbeddingService
    let vectorSearchService: any VectorSearchServiceProtocol
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

    // MARK: - Init (private — use open(at:engineFactory:))

    private init(
        projectURL: URL,
        databaseService: any DatabaseServiceProtocol,
        engineStore: TerminalEngineStore,
        sessionRepository: any SessionRepositoryProtocol,
        noteRepository: any NoteRepositoryProtocol,
        sessionMessageRepository: any SessionMessageRepositoryProtocol,
        harnessEventRepository: any HarnessEventRepositoryProtocol,
        ruleFileRepository: any RuleFileRepositoryProtocol,
        sessionSnapshotRepository: any SessionSnapshotRepositoryProtocol,
        sessionStore: SessionStore,
        agentStateStore: AgentStateStore,
        searchService: any SearchServiceProtocol,
        sessionArchiveService: SessionArchiveService,
        sessionHandoffService: any SessionHandoffServiceProtocol,
        contextInjectionService: any ContextInjectionServiceProtocol,
        experienceCodifier: ExperienceCodifier,
        branchSummarizer: BranchSummarizer,
        embeddingService: EmbeddingService,
        vectorSearchService: any VectorSearchServiceProtocol,
        gitService: any GitServiceProtocol,
        commandRouter: CommandRouter,
        tokenCountingService: any TokenCountingServiceProtocol,
        metricsCollector: any MetricsCollectorProtocol,
        dbHealthMonitor: DBHealthMonitor,
        crashContext: CrashContext,
        notesViewModel: NotesViewModel,
        projectViewModel: ProjectViewModel
    ) {
        self.projectURL = projectURL
        self.databaseService = databaseService
        self.engineStore = engineStore
        self.sessionRepository = sessionRepository
        self.noteRepository = noteRepository
        self.sessionMessageRepository = sessionMessageRepository
        self.harnessEventRepository = harnessEventRepository
        self.ruleFileRepository = ruleFileRepository
        self.sessionSnapshotRepository = sessionSnapshotRepository
        self.sessionStore = sessionStore
        self.agentStateStore = agentStateStore
        self.searchService = searchService
        self.sessionArchiveService = sessionArchiveService
        self.sessionHandoffService = sessionHandoffService
        self.contextInjectionService = contextInjectionService
        self.experienceCodifier = experienceCodifier
        self.branchSummarizer = branchSummarizer
        self.embeddingService = embeddingService
        self.vectorSearchService = vectorSearchService
        self.gitService = gitService
        self.commandRouter = commandRouter
        self.tokenCountingService = tokenCountingService
        self.metricsCollector = metricsCollector
        self.dbHealthMonitor = dbHealthMonitor
        self.crashContext = crashContext
        self.notesViewModel = notesViewModel
        self.projectViewModel = projectViewModel
    }

    /// Project display name (directory basename).
    var displayName: String { projectURL.lastPathComponent }

    // MARK: - Feature scopes (injected into SwiftUI environment)

    private(set) lazy var sessionScope = SessionScope(
        store: sessionStore,
        engines: engineStore,
        agentStates: agentStateStore
    )

    private(set) lazy var dataScope = DataScope(
        searchService: searchService,
        vectorSearchService: vectorSearchService,
        ruleFileRepository: ruleFileRepository,
        sessionMessageRepository: sessionMessageRepository
    )

    private(set) lazy var projectScope = ProjectScope(
        gitService: gitService,
        viewModel: projectViewModel
    )

    private(set) lazy var viewStateManager = SessionViewStateManager(
        commandRouter: commandRouter,
        sessionStore: sessionStore,
        tokenCountingService: tokenCountingService,
        agentStateStore: agentStateStore,
        contextInjectionService: contextInjectionService,
        sessionHandoffService: sessionHandoffService,
        metricsCollector: metricsCollector
    )

    // MARK: - Factory

    /// Opens a project, creating `<projectURL>/.termura/termura.db` if needed.
    static func open(
        at projectURL: URL,
        engineFactory: any TerminalEngineFactory,
        tokenCountingService: any TokenCountingServiceProtocol,
        metricsCollector: (any MetricsCollectorProtocol)? = nil
    ) throws -> ProjectContext {
        let fallbackMetrics: any MetricsCollectorProtocol = metricsCollector ?? MetricsCollector()
        let db = try DatabaseService(pool: DatabaseService.makePool(at: projectURL), metrics: fallbackMetrics)
        let repos = makeRepositories(db: db)
        let services = makeServices(
            repos: repos, projectURL: projectURL, engineFactory: engineFactory,
            metricsCollector: fallbackMetrics
        )
        let healthMonitor = DBHealthMonitor(db: db, metrics: fallbackMetrics)
        let crashCtx = CrashContext(metrics: fallbackMetrics)
        Task { await healthMonitor.start() }

        // Lifecycle: one-shot housekeeping — gitignore management is non-critical.
        let url = projectURL
        Task.detached { ensureProjectGitignore(at: url) }
        logger.info("Opened project at \(projectURL.path)")

        return ProjectContext(
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
            branchSummarizer: services.summarizer,
            embeddingService: services.embedding,
            vectorSearchService: services.vector,
            gitService: services.git,
            commandRouter: services.router,
            tokenCountingService: tokenCountingService,
            metricsCollector: fallbackMetrics,
            dbHealthMonitor: healthMonitor,
            crashContext: crashCtx,
            notesViewModel: NotesViewModel(repository: repos.note),
            projectViewModel: ProjectViewModel(
                gitService: services.git,
                projectRoot: projectURL.path,
                commandRouter: services.router
            )
        )
    }

    // MARK: - Factory helpers

    private struct Repos {
        let session: any SessionRepositoryProtocol
        let note: any NoteRepositoryProtocol
        let message: any SessionMessageRepositoryProtocol
        let harness: any HarnessEventRepositoryProtocol
        let rule: any RuleFileRepositoryProtocol
        let snapshot: any SessionSnapshotRepositoryProtocol
    }

    private static func makeRepositories(db: any DatabaseServiceProtocol) -> Repos {
        Repos(
            session: SessionRepository(db: db),
            note: NoteRepository(db: db),
            message: SessionMessageRepository(db: db),
            harness: HarnessEventRepository(db: db),
            rule: RuleFileRepository(db: db),
            snapshot: SessionSnapshotRepository(db: db)
        )
    }

    private struct Svc {
        let engineStore: TerminalEngineStore
        let sessionStore: SessionStore
        let agentState: AgentStateStore
        let search: any SearchServiceProtocol
        let archive: SessionArchiveService
        let summarizer: BranchSummarizer
        let handoff: any SessionHandoffServiceProtocol
        let injection: any ContextInjectionServiceProtocol
        let codifier: ExperienceCodifier
        let embedding: EmbeddingService
        let vector: any VectorSearchServiceProtocol
        let git: any GitServiceProtocol
        let router: CommandRouter
    }

    private static func makeServices(
        repos: Repos, projectURL: URL, engineFactory: any TerminalEngineFactory,
        metricsCollector: any MetricsCollectorProtocol
    ) -> Svc {
        let eng = TerminalEngineStore(factory: engineFactory)
        let sum = BranchSummarizer()
        let hoff = SessionHandoffService(
            messageRepo: repos.message, harnessEventRepo: repos.harness, summarizer: sum
        )
        let emb = EmbeddingService()
        return Svc(
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
            summarizer: sum, handoff: hoff,
            injection: ContextInjectionService(handoffService: hoff),
            codifier: ExperienceCodifier(harnessEventRepo: repos.harness),
            embedding: emb, vector: VectorSearchService(embeddingService: emb),
            git: GitService(), router: CommandRouter()
        )
    }
}
