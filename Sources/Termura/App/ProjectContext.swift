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
    let searchService: SearchService
    let sessionArchiveService: SessionArchiveService
    let sessionHandoffService: SessionHandoffService
    let contextInjectionService: ContextInjectionService
    let experienceCodifier: ExperienceCodifier
    let branchSummarizer: BranchSummarizer
    let embeddingService: EmbeddingService
    let vectorSearchService: VectorSearchService

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
        searchService: SearchService,
        sessionArchiveService: SessionArchiveService,
        sessionHandoffService: SessionHandoffService,
        contextInjectionService: ContextInjectionService,
        experienceCodifier: ExperienceCodifier,
        branchSummarizer: BranchSummarizer,
        embeddingService: EmbeddingService,
        vectorSearchService: VectorSearchService
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
    }

    /// Project display name (directory basename).
    var displayName: String { projectURL.lastPathComponent }

    // MARK: - Factory

    /// Opens a project, creating `<projectURL>/.termura/termura.db` if needed.
    static func open(
        at projectURL: URL,
        engineFactory: any TerminalEngineFactory
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

        ensureGitignore(at: projectURL)
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
            vectorSearchService: vector
        )
    }

    // MARK: - Teardown

    func close() {
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
