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
            logger.warning("Could not update .gitignore: \(error)")
        }
    } else {
        let gitDir = projectURL.appendingPathComponent(".git")
        guard fileManager.fileExists(atPath: gitDir.path) else { return }
        do {
            try (entry + "\n").write(to: gitignoreURL, atomically: true, encoding: .utf8)
            logger.info("Created .gitignore with \(entry)")
        } catch {
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
        metricsCollector: (any MetricsCollectorProtocol)? = nil, // Optional: observability, nil = MetricsCollector()
        notificationService: (any NotificationServiceProtocol)? = nil // Optional: observability, nil = no-op
    ) async throws -> ProjectContext {
        let fallbackMetrics: any MetricsCollectorProtocol = metricsCollector ?? MetricsCollector()
        // Ensure .termura/ is in .gitignore BEFORE any files are written to .termura/.
        // Must complete before makePool creates the directory, otherwise a `git add .`
        // between directory creation and gitignore update could capture sensitive files.
        await Task.detached { ensureProjectGitignore(at: projectURL) }.value
        // makePool is non-isolated async — awaiting it suspends MainActor and runs
        // filesystem + SQLite work on the cooperative thread pool (CLAUDE.md §6, Principle 6).
        let pool = try await DatabaseService.makePool(at: projectURL)
        let db = try await DatabaseService(pool: pool, metrics: fallbackMetrics)
        let repos = makeRepositories(db: db)
        let services = makeServices(
            repos: repos, projectURL: projectURL,
            engineFactory: engineFactory, metricsCollector: fallbackMetrics
        )
        let healthMonitor = DBHealthMonitor(db: db, metrics: fallbackMetrics)
        let crashCtx = CrashContext(metrics: fallbackMetrics)
        // open(at:) is async throws — await the actor hop directly, no Task wrapper needed.
        await healthMonitor.start()

        logger.info("Opened project at \(projectURL.path)")
        let projectVM = ProjectViewModel(
            gitService: services.git, projectRoot: projectURL.path,
            commandRouter: services.router, fileTreeService: FileTreeService()
        )
        let infra = ProjectContext.InfrastructureComponents(
            databaseService: db, dbHealthMonitor: healthMonitor, crashContext: crashCtx,
            metricsCollector: fallbackMetrics, tokenCountingService: tokenCountingService
        )
        let scopes = makeScopes(
            repos: repos, services: services,
            supplements: ScopeSupplements(
                tokenCountingService: tokenCountingService,
                metricsCollector: fallbackMetrics,
                notificationService: notificationService,
                projectVM: projectVM
            )
        )
        return ProjectContext(makeComponents(
            projectURL: projectURL, infra: infra,
            repos: repos, services: services, scopes: scopes
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

    private struct ScopeSupplements {
        let tokenCountingService: any TokenCountingServiceProtocol
        let metricsCollector: any MetricsCollectorProtocol
        let notificationService: (any NotificationServiceProtocol)?
        let projectVM: ProjectViewModel
    }

    private struct ProjectScopes {
        let session: SessionScope
        let data: DataScope
        let project: ProjectScope
        let viewState: SessionViewStateManager
    }

    /// Assembles the full `Components` value passed to `ProjectContext.init`.
    /// Extracted from `open(at:)` to keep that function within the 60-line body limit.
    private static func makeComponents(
        projectURL: URL,
        infra: ProjectContext.InfrastructureComponents,
        repos: ProjectRepositories,
        services: ProjectServices,
        scopes: ProjectScopes
    ) -> Components {
        let notesVM = NotesViewModel(repository: repos.note)
        return Components(
            projectURL: projectURL,
            infrastructure: infra,
            repositories: ProjectContext.RepositoryComponents(
                session: repos.session, note: repos.note, message: repos.message,
                harness: repos.harness, rule: repos.rule, snapshot: repos.snapshot
            ),
            services: ProjectContext.ServiceComponents(
                engineStore: services.engineStore, sessionStore: services.sessionStore,
                agentStateStore: services.agentState, searchService: services.search,
                sessionArchiveService: services.archive, sessionHandoffService: services.handoff,
                contextInjectionService: services.injection, experienceCodifier: services.codifier,
                gitService: services.git, commandRouter: services.router
            ),
            viewModels: ProjectContext.ViewModelComponents(
                notesViewModel: notesVM, projectViewModel: scopes.project.viewModel
            ),
            scopes: ProjectContext.ScopeComponents(
                sessionScope: scopes.session, dataScope: scopes.data,
                projectScope: scopes.project, viewStateManager: scopes.viewState
            )
        )
    }

    private static func makeScopes(
        repos: ProjectRepositories,
        services: ProjectServices,
        supplements: ScopeSupplements
    ) -> ProjectScopes {
        let session = SessionScope(
            store: services.sessionStore, engines: services.engineStore, agentStates: services.agentState
        )
        let data = DataScope(
            searchService: services.search, vectorSearchService: nil,
            ruleFileRepository: repos.rule, sessionMessageRepository: repos.message
        )
        let viewState = SessionViewStateManager(SessionViewStateManager.Components(
            commandRouter: services.router,
            sessionStore: services.sessionStore,
            tokenCountingService: supplements.tokenCountingService,
            agentStateStore: services.agentState,
            contextInjectionService: services.injection,
            sessionHandoffService: services.handoff,
            metricsCollector: supplements.metricsCollector,
            notificationService: supplements.notificationService
        ))
        return ProjectScopes(
            session: session, data: data,
            project: ProjectScope(
                gitService: services.git,
                viewModel: supplements.projectVM,
                diagnosticsStore: DiagnosticsStore(
                    commandRouter: services.router,
                    projectRoot: supplements.projectVM.projectRootPath
                )
            ),
            viewState: viewState
        )
    }
}
