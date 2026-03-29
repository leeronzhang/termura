import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectContext")

/// Appends `.termura/` to the project's `.gitignore` if not already present.
/// Accepts an injectable `fileManager` for testability; defaults to `FileManager.default`.
func ensureProjectGitignore(
    at projectURL: URL,
    fileManager: any FileManagerProtocol = FileManager.default
) {
    let gitignoreURL = projectURL.appendingPathComponent(".gitignore")
    let entry = ".termura/"

    if fileManager.fileExists(atPath: gitignoreURL.path) {
        let contents: String
        do {
            contents = try String(contentsOf: gitignoreURL, encoding: .utf8)
        } catch {
            // Non-critical: gitignore management is a convenience feature; project works without it.
            logger.warning("Could not read .gitignore: \(error)")
            return
        }
        let lines = contents.components(separatedBy: .newlines)
        if lines.contains(where: { line in
            line.trimmingCharacters(in: .whitespaces) == entry
        }) { return }
        let suffix = contents.hasSuffix("\n") ? entry + "\n" : "\n" + entry + "\n"
        do {
            try (contents + suffix).write(to: gitignoreURL, atomically: true, encoding: .utf8)
            logger.info("Appended \(entry) to .gitignore")
        } catch {
            // Non-critical: gitignore update is a convenience; does not affect app operation.
            logger.warning("Could not update .gitignore: \(error)")
        }
    } else {
        let gitDir = projectURL.appendingPathComponent(".git")
        guard fileManager.fileExists(atPath: gitDir.path) else { return }
        do {
            try (entry + "\n").write(to: gitignoreURL, atomically: true, encoding: .utf8)
            logger.info("Created .gitignore with \(entry)")
        } catch {
            // Non-critical: gitignore creation is a convenience; does not affect app operation.
            logger.warning("Could not create .gitignore: \(entry)")
        }
    }
}

// MARK: - ProjectContext Factory

extension ProjectContext {
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
            gitService: services.git, projectRoot: projectURL.path,
            commandRouter: services.router, fileTreeService: FileTreeService()
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
