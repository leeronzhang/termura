import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectContext")

/// Per-project dependency container. Each window owns exactly one `ProjectContext`
/// whose services are backed by `<projectURL>/.termura/termura.db`.
@MainActor
final class ProjectContext: ObservableObject {
    let projectURL: URL

    // MARK: - Core infrastructure

    let databaseService: DatabaseService
    let engineStore: TerminalEngineStore

    // MARK: - Repositories

    let sessionRepository: SessionRepository
    let noteRepository: NoteRepository
    let sessionMessageRepository: SessionMessageRepository
    let harnessEventRepository: HarnessEventRepository
    let ruleFileRepository: RuleFileRepository
    let sessionSnapshotRepository: SessionSnapshotRepository

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
    let gitService: GitService
    let commandRouter: CommandRouter
    /// Global service — referenced per-project for environment injection.
    let tokenCountingService: any TokenCountingServiceProtocol
    /// Per-project notes ViewModel — created here so views can share it via @EnvironmentObject.
    let notesViewModel: NotesViewModel

    /// Per-project file tree ViewModel — owned here so expanded state survives
    /// sidebar re-evaluations. Views receive it as @ObservedObject.
    let projectViewModel: ProjectViewModel

    // MARK: - Init (private — use open(at:engineFactory:))

    private init(
        projectURL: URL,
        databaseService: DatabaseService,
        engineStore: TerminalEngineStore,
        sessionRepository: SessionRepository,
        noteRepository: NoteRepository,
        sessionMessageRepository: SessionMessageRepository,
        harnessEventRepository: HarnessEventRepository,
        ruleFileRepository: RuleFileRepository,
        sessionSnapshotRepository: SessionSnapshotRepository,
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
        gitService: GitService,
        commandRouter: CommandRouter,
        tokenCountingService: any TokenCountingServiceProtocol,
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
        self.notesViewModel = notesViewModel
        self.projectViewModel = projectViewModel
    }

    /// Project display name (directory basename).
    var displayName: String { projectURL.lastPathComponent }

    // MARK: - Factory

    /// Opens a project, creating `<projectURL>/.termura/termura.db` if needed.
    static func open(
        at projectURL: URL,
        engineFactory: any TerminalEngineFactory,
        tokenCountingService: TokenCountingService
    ) throws -> ProjectContext {
        let db = try DatabaseService(pool: DatabaseService.makePool(at: projectURL))
        let repos = makeRepositories(db: db)
        let services = makeServices(repos: repos, projectURL: projectURL, engineFactory: engineFactory)

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
            notesViewModel: NotesViewModel(repository: repos.note),
            projectViewModel: ProjectViewModel(
                gitService: services.git,
                projectRoot: projectURL.path,
                commandRouter: services.router
            )
        )
    }

    // MARK: - Per-session view state cache

    /// Cached per-session view objects. Lazily created on first access, removed on session close.
    private(set) var sessionViewStates: [SessionID: SessionViewState] = [:]

    /// Per-session OutputStore references — used by AppDelegate for termination handoff.
    private(set) var outputStores: [SessionID: OutputStore] = [:]

    // MARK: - View state mutation API (for cross-file extensions)

    func setViewState(_ state: SessionViewState?, for id: SessionID) {
        sessionViewStates[id] = state
    }

    func setOutputStore(_ store: OutputStore?, for id: SessionID) {
        outputStores[id] = store
    }

    func clearAllCaches() {
        sessionViewStates.removeAll()
        outputStores.removeAll()
    }

    // MARK: - Factory helpers

    private struct Repos {
        let session: SessionRepository
        let note: NoteRepository
        let message: SessionMessageRepository
        let harness: HarnessEventRepository
        let rule: RuleFileRepository
        let snapshot: SessionSnapshotRepository
    }

    private static func makeRepositories(db: DatabaseService) -> Repos {
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
        let search: SearchService
        let archive: SessionArchiveService
        let summarizer: BranchSummarizer
        let handoff: SessionHandoffService
        let injection: ContextInjectionService
        let codifier: ExperienceCodifier
        let embedding: EmbeddingService
        let vector: VectorSearchService
        let git: GitService
        let router: CommandRouter
    }

    private static func makeServices(
        repos: Repos, projectURL: URL, engineFactory: any TerminalEngineFactory
    ) -> Svc {
        let eng = TerminalEngineStore(factory: engineFactory)
        let sum = BranchSummarizer()
        let hoff = SessionHandoffService(
            messageRepo: repos.message, harnessEventRepo: repos.harness, summarizer: sum
        )
        let emb = EmbeddingService()
        return Svc(
            engineStore: eng,
            sessionStore: SessionStore(engineStore: eng, projectRoot: projectURL.path, repository: repos.session),
            agentState: AgentStateStore(),
            search: SearchService(sessionRepository: repos.session, noteRepository: repos.note),
            archive: SessionArchiveService(repository: repos.session),
            summarizer: sum, handoff: hoff,
            injection: ContextInjectionService(handoffService: hoff),
            codifier: ExperienceCodifier(harnessEventRepo: repos.harness),
            embedding: emb, vector: VectorSearchService(embeddingService: emb),
            git: GitService(), router: CommandRouter()
        )
    }
}
