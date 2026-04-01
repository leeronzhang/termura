import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectContext")

/// Per-project composition root. Each window owns exactly one `ProjectContext`
/// whose services are backed by `<projectURL>/.termura/termura.db`.
/// Not injected into views — feature-scoped containers (SessionScope, DataScope,
/// ProjectScope, SessionViewStateManager) are injected via @Environment instead.
///
/// Public surface (9 properties): projectURL, commandRouter, sessionHandoffService,
/// notesViewModel, viewStateManager, sessionScope, dataScope, projectScope.
/// All infrastructure (repositories, services, monitors) is private.
@MainActor
final class ProjectContext {
    let projectURL: URL

    // MARK: - Public interface

    let commandRouter: CommandRouter
    /// Needed by ProjectCoordinator for termination handoff generation.
    let sessionHandoffService: any SessionHandoffServiceProtocol
    /// Per-project notes ViewModel — shared via @Environment.
    let notesViewModel: NotesViewModel

    // MARK: - Feature scopes (injected into SwiftUI environment)

    let sessionScope: SessionScope
    let dataScope: DataScope
    let projectScope: ProjectScope
    let viewStateManager: SessionViewStateManager

    // MARK: - Private infrastructure

    private let databaseService: any DatabaseServiceProtocol
    private let engineStore: TerminalEngineStore
    private let sessionRepository: any SessionRepositoryProtocol
    private let noteRepository: any NoteRepositoryProtocol
    private let sessionMessageRepository: any SessionMessageRepositoryProtocol
    private let harnessEventRepository: any HarnessEventRepositoryProtocol
    private let ruleFileRepository: any RuleFileRepositoryProtocol
    private let sessionSnapshotRepository: any SessionSnapshotRepositoryProtocol
    private let sessionStore: SessionStore
    private let agentStateStore: AgentStateStore
    private let searchService: any SearchServiceProtocol
    private let sessionArchiveService: SessionArchiveService
    private let contextInjectionService: any ContextInjectionServiceProtocol
    private let experienceCodifier: ExperienceCodifier
    private let gitService: any GitServiceProtocol
    private let tokenCountingService: any TokenCountingServiceProtocol
    private let metricsCollector: any MetricsCollectorProtocol
    private let dbHealthMonitor: DBHealthMonitor
    private let crashContext: CrashContext
    private let projectViewModel: ProjectViewModel

    // MARK: - Init (private — use open(at:engineFactory:))

    /// Second-level grouping structs: each of the 28 dependencies is assigned by label
    /// within a semantically bounded sub-struct, preventing same-typed arg swaps.
    struct InfrastructureComponents {
        let databaseService: any DatabaseServiceProtocol
        let dbHealthMonitor: DBHealthMonitor
        let crashContext: CrashContext
        let metricsCollector: any MetricsCollectorProtocol
        let tokenCountingService: any TokenCountingServiceProtocol
    }

    struct RepositoryComponents {
        let session: any SessionRepositoryProtocol
        let note: any NoteRepositoryProtocol
        let message: any SessionMessageRepositoryProtocol
        let harness: any HarnessEventRepositoryProtocol
        let rule: any RuleFileRepositoryProtocol
        let snapshot: any SessionSnapshotRepositoryProtocol
    }

    struct ServiceComponents {
        let engineStore: TerminalEngineStore
        let sessionStore: SessionStore
        let agentStateStore: AgentStateStore
        let searchService: any SearchServiceProtocol
        let sessionArchiveService: SessionArchiveService
        let sessionHandoffService: any SessionHandoffServiceProtocol
        let contextInjectionService: any ContextInjectionServiceProtocol
        let experienceCodifier: ExperienceCodifier
        let gitService: any GitServiceProtocol
        let commandRouter: CommandRouter
    }

    struct ViewModelComponents {
        let notesViewModel: NotesViewModel
        let projectViewModel: ProjectViewModel
    }

    struct ScopeComponents {
        let sessionScope: SessionScope
        let dataScope: DataScope
        let projectScope: ProjectScope
        let viewStateManager: SessionViewStateManager
    }

    struct Components {
        let projectURL: URL
        let infrastructure: InfrastructureComponents
        let repositories: RepositoryComponents
        let services: ServiceComponents
        let viewModels: ViewModelComponents
        let scopes: ScopeComponents
    }

    init(_ components: Components) {
        projectURL = components.projectURL

        databaseService = components.infrastructure.databaseService
        dbHealthMonitor = components.infrastructure.dbHealthMonitor
        crashContext = components.infrastructure.crashContext
        metricsCollector = components.infrastructure.metricsCollector
        tokenCountingService = components.infrastructure.tokenCountingService

        sessionRepository = components.repositories.session
        noteRepository = components.repositories.note
        sessionMessageRepository = components.repositories.message
        harnessEventRepository = components.repositories.harness
        ruleFileRepository = components.repositories.rule
        sessionSnapshotRepository = components.repositories.snapshot

        engineStore = components.services.engineStore
        sessionStore = components.services.sessionStore
        agentStateStore = components.services.agentStateStore
        searchService = components.services.searchService
        sessionArchiveService = components.services.sessionArchiveService
        sessionHandoffService = components.services.sessionHandoffService
        contextInjectionService = components.services.contextInjectionService
        experienceCodifier = components.services.experienceCodifier
        gitService = components.services.gitService
        commandRouter = components.services.commandRouter

        notesViewModel = components.viewModels.notesViewModel
        projectViewModel = components.viewModels.projectViewModel

        sessionScope = components.scopes.sessionScope
        dataScope = components.scopes.dataScope
        projectScope = components.scopes.projectScope
        viewStateManager = components.scopes.viewStateManager
    }

    /// Project display name (directory basename).
    var displayName: String { projectURL.lastPathComponent }

    // MARK: - Teardown

    /// Flushes all pending persistence writes (sessions + notes) to guarantee
    /// in-memory state is fully written to DB before shutdown or window close.
    func flushPendingWrites() async {
        await sessionScope.store.flushPendingWrites()
        await notesViewModel.flushPendingWrites()
        await viewStateManager.flushPendingHandoffs()
    }

    func close() {
        viewStateManager.clearAll()
        sessionScope.engines.terminateAll()
        let monitor = dbHealthMonitor
        Task { await monitor.stop() }
        let path = projectURL.path
        logger.info("Closed project at \(path)")
    }

}
