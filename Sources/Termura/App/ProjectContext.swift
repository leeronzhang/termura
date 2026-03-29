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

    /// Named struct ensures each of the 28 dependencies is assigned by label, preventing same-typed arg swaps.
    struct Components {
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

    init(_ components: Components) {
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

    // MARK: - Teardown

    /// Flushes all pending persistence writes (sessions + notes) to guarantee
    /// in-memory state is fully written to DB before shutdown or window close.
    func flushPendingWrites() async {
        await sessionScope.store.flushPendingWrites()
        await notesViewModel.flushPendingWrites()
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
