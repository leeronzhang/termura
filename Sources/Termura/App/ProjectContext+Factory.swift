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
        // Ensure .termura/ is in .gitignore before DB setup, otherwise a `git add .`
        // between directory creation and gitignore update could capture sensitive files.
        // WHY: Gitignore repair must leave MainActor before DB setup.
        // OWNER: Factory owns this one-shot task; TEARDOWN: awaited inline before proceeding.
        // TEST: Cover gitignore repair before initial project DB/materialization.
        await Task.detached { ensureProjectGitignore(at: projectURL) }.value
        // makePool is non-isolated async — awaiting it suspends MainActor and runs
        // filesystem + SQLite work on the cooperative thread pool (CLAUDE.md §6, Principle 6).
        let pool = try await DatabaseService.makePool(at: projectURL)
        let db = try await DatabaseService(pool: pool, metrics: fallbackMetrics)

        // P1: Establish knowledge/{notes,sources,log,attachments}/ structure and
        // migrate legacy <project>/.termura/notes/ to knowledge/notes/ if present.
        let knowledgeMigration = KnowledgeStructureMigrationService(projectURL: projectURL)
        do {
            _ = try await knowledgeMigration.ensureStructure()
        } catch {
            logger.error("Knowledge structure setup failed: \(error.localizedDescription)")
        }

        let repos = makeRepositories(db: db, projectURL: projectURL)

        // One-time migration: export legacy GRDB notes to Markdown files (in the new location).
        let notesDir = Self.notesDirectory(for: projectURL)
        let migration = NoteMigrationService(
            db: db, fileService: NoteFileService(), notesDirectory: notesDir
        )
        do {
            _ = try await migration.migrateIfNeeded()
        } catch let migrationError as NoteMigrationService.MigrationError {
            // Partial failure: some notes failed to export. The sentinel was NOT written,
            // so the next launch will retry. Log and continue opening the project.
            logger.error("Note migration partial failure; will retry next launch: \(migrationError.localizedDescription)")
        }

        // Start file-system watcher for external note changes.
        try await repos.note.startWatching()

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

    /// Builds the absolute URL of the curated notes directory for a project.
    /// Single source of truth — replaces the four ad-hoc constructions of this path.
    static func notesDirectory(for projectURL: URL) -> URL {
        projectURL
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.Knowledge.directoryName)
            .appendingPathComponent(AppConfig.Knowledge.notesSubdirectory)
    }

    struct ProjectRepositories {
        let session: any SessionRepositoryProtocol
        let note: any NoteRepositoryProtocol
        let message: any SessionMessageRepositoryProtocol
        let harness: any HarnessEventRepositoryProtocol
        let rule: any RuleFileRepositoryProtocol
        let snapshot: any SessionSnapshotRepositoryProtocol
    }

    static func makeRepositories(
        db: any DatabaseServiceProtocol,
        projectURL: URL
    ) -> ProjectRepositories {
        #if HARNESS_ENABLED
        let ruleRepo: any RuleFileRepositoryProtocol = RuleFileRepository(db: db)
        #else
        let ruleRepo: any RuleFileRepositoryProtocol = NullRuleFileRepository()
        #endif
        let notesDir = notesDirectory(for: projectURL)
        let noteRepo = FileBackedNoteRepository(
            notesDirectory: notesDir, fileService: NoteFileService(), db: db
        )
        return ProjectRepositories(
            session: SessionRepository(db: db),
            note: noteRepo,
            message: SessionMessageRepository(db: db),
            harness: HarnessEventRepository(db: db),
            rule: ruleRepo,
            snapshot: SessionSnapshotRepository(db: db)
        )
    }

    /// Assembles the full `Components` value passed to `ProjectContext.init`.
    /// Extracted from `open(at:)` to keep that function within the 60-line body limit.
    static func makeComponents(
        projectURL: URL,
        infra: ProjectContext.InfrastructureComponents,
        repos: ProjectRepositories,
        services: ProjectServices,
        scopes: ProjectScopes
    ) -> Components {
        let notesDir = Self.notesDirectory(for: projectURL)
        let notesVM = NotesViewModel(
            repository: repos.note, notesDirectoryURL: notesDir
        )
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
}
