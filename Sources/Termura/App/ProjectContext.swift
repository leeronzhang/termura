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
    lazy var projectViewModel: ProjectViewModel = ProjectViewModel(
        gitService: gitService,
        projectRoot: projectURL.path,
        commandRouter: commandRouter
    )

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
        notesViewModel: NotesViewModel
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
        let pool = try DatabaseService.makePool(at: projectURL)
        let db = try DatabaseService(pool: pool)

        let sessionRepo = SessionRepository(db: db)
        let noteRepo = NoteRepository(db: db)
        let msgRepo = SessionMessageRepository(db: db)
        let harnessRepo = HarnessEventRepository(db: db)
        let ruleRepo = RuleFileRepository(db: db)
        let snapshotRepo = SessionSnapshotRepository(db: db)

        let engineStore = TerminalEngineStore(factory: engineFactory)
        let sessionStore = SessionStore(
            engineStore: engineStore,
            projectRoot: projectURL.path,
            repository: sessionRepo
        )

        let agentState = AgentStateStore()
        let search = SearchService(
            sessionRepository: sessionRepo,
            noteRepository: noteRepo
        )
        let archive = SessionArchiveService(repository: sessionRepo)
        let summarizer = BranchSummarizer()
        let handoff = SessionHandoffService(
            messageRepo: msgRepo,
            harnessEventRepo: harnessRepo,
            summarizer: summarizer
        )
        let injection = ContextInjectionService(handoffService: handoff)
        let codifier = ExperienceCodifier(harnessEventRepo: harnessRepo)
        let embedding = EmbeddingService()
        let vector = VectorSearchService(embeddingService: embedding)
        let git = GitService()
        let router = CommandRouter()

        let url = projectURL
        Task.detached { await Self.ensureGitignore(at: url) }
        logger.info("Opened project at \(projectURL.path)")

        return ProjectContext(
            projectURL: projectURL,
            databaseService: db,
            engineStore: engineStore,
            sessionRepository: sessionRepo,
            noteRepository: noteRepo,
            sessionMessageRepository: msgRepo,
            harnessEventRepository: harnessRepo,
            ruleFileRepository: ruleRepo,
            sessionSnapshotRepository: snapshotRepo,
            sessionStore: sessionStore,
            agentStateStore: agentState,
            searchService: search,
            sessionArchiveService: archive,
            sessionHandoffService: handoff,
            contextInjectionService: injection,
            experienceCodifier: codifier,
            branchSummarizer: summarizer,
            embeddingService: embedding,
            vectorSearchService: vector,
            gitService: git,
            commandRouter: router,
            tokenCountingService: tokenCountingService,
            notesViewModel: NotesViewModel(repository: noteRepo)
        )
    }

    // MARK: - Per-session view state cache

    /// Cached per-session view objects. Lazily created on first access, removed on session close.
    /// This avoids the fragile `@StateObject`-in-init pattern — views receive these
    /// as `@ObservedObject`, and the cache owns the lifecycle.
    private(set) var sessionViewStates: [SessionID: SessionViewState] = [:]

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
        sessionViewStates.removeValue(forKey: sessionID)
        outputStores.removeValue(forKey: sessionID)
    }

    // MARK: - OutputStore registry

    /// Per-session OutputStore references — used by AppDelegate for termination handoff.
    private(set) var outputStores: [SessionID: OutputStore] = [:]

    func registerOutputStore(_ store: OutputStore, for sessionID: SessionID) {
        outputStores[sessionID] = store
    }

    func unregisterOutputStore(for sessionID: SessionID) {
        outputStores.removeValue(forKey: sessionID)
    }

    // MARK: - Teardown

    func close() {
        sessionViewStates.removeAll()
        outputStores.removeAll()
        engineStore.terminateAll()
        let path = projectURL.path
        logger.info("Closed project at \(path)")
    }

    // MARK: - .gitignore management

    /// Appends `.termura/` to the project's `.gitignore` if not already present.
    private static func ensureGitignore(at projectURL: URL) {
        let gitignoreURL = projectURL.appendingPathComponent(".gitignore")
        let entry = ".termura/"

        if FileManager.default.fileExists(atPath: gitignoreURL.path) {
            let contents: String
            do {
                contents = try String(contentsOf: gitignoreURL, encoding: .utf8)
            } catch {
                logger.warning("Could not read .gitignore: \(error)")
                return
            }
            let lines = contents.components(separatedBy: .newlines)
            if lines.contains(where: { line in line.trimmingCharacters(in: .whitespaces) == entry }) { return }
            // Append with newline safety
            let suffix = contents.hasSuffix("\n") ? entry + "\n" : "\n" + entry + "\n"
            do {
                try (contents + suffix).write(to: gitignoreURL, atomically: true, encoding: .utf8)
                logger.info("Appended \(entry) to .gitignore")
            } catch {
                logger.warning("Could not update .gitignore: \(error)")
            }
        } else {
            // Only create .gitignore if a .git directory exists (i.e., it's a git repo)
            let gitDir = projectURL.appendingPathComponent(".git")
            guard FileManager.default.fileExists(atPath: gitDir.path) else { return }
            do {
                try (entry + "\n").write(to: gitignoreURL, atomically: true, encoding: .utf8)
                logger.info("Created .gitignore with \(entry)")
            } catch {
                logger.warning("Could not create .gitignore: \(error)")
            }
        }
    }
}
