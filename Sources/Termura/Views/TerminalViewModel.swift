import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalViewModel")

/// ViewModel bridging the terminal engine with output chunking, token counting,
/// and session metadata for the terminal area view hierarchy.
///
/// Delegates agent detection/state to `AgentCoordinator`, output chunking/tokens
/// to `OutputProcessor`, and context injection/handoff to `SessionServices`.
@MainActor
final class TerminalViewModel: ObservableObject {
    // MARK: - Published state

    @Published var currentMetadata: SessionMetadata
    /// True while an interactive tool (Claude Code `>`) is showing its prompt.
    @Published var isInteractivePrompt: Bool = false
    /// Currently pending risk alert (shown as sheet).
    @Published var pendingRiskAlert: RiskAlert?
    /// Context window warning alert (shown as sheet).
    @Published var contextWindowAlert: ContextWindowAlert?

    // MARK: - Dependencies

    let sessionID: SessionID
    let engine: any TerminalEngine
    let sessionStore: any SessionStoreProtocol
    let modeController: InputModeController
    let agentCoordinator: AgentCoordinator
    let outputProcessor: OutputProcessor
    let sessionServices: SessionServices
    let clock: any AppClock
    let sessionStartTime: Date = .init()

    // MARK: - Internal state

    /// Debounced re-check for prompt detection after PTY output settles.
    var promptRecheckTask: Task<Void, Never>?
    /// Bounded executor for background tasks.
    private let taskExecutor: BoundedTaskExecutor
    private var streamTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    init(
        sessionID: SessionID,
        engine: any TerminalEngine,
        sessionStore: any SessionStoreProtocol,
        modeController: InputModeController,
        agentCoordinator: AgentCoordinator,
        outputProcessor: OutputProcessor,
        sessionServices: SessionServices,
        initialWorkingDirectory: String = AppConfig.Paths.homeDirectory,
        clock: any AppClock = LiveClock()
    ) {
        self.sessionID = sessionID
        self.engine = engine
        self.sessionStore = sessionStore
        self.modeController = modeController
        self.agentCoordinator = agentCoordinator
        self.outputProcessor = outputProcessor
        self.sessionServices = sessionServices
        self.clock = clock
        taskExecutor = BoundedTaskExecutor(maxConcurrent: AppConfig.Runtime.maxConcurrentSessionTasks)

        currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: initialWorkingDirectory
        )

        // Forward @Published state from AgentCoordinator to keep view bindings stable.
        agentCoordinator.$pendingRiskAlert
            .receive(on: RunLoop.main)
            .sink { [weak self] alert in self?.pendingRiskAlert = alert }
            .store(in: &cancellables)
        agentCoordinator.$contextWindowAlert
            .receive(on: RunLoop.main)
            .sink { [weak self] alert in self?.contextWindowAlert = alert }
            .store(in: &cancellables)

        subscribeToOutput()
        subscribeToShellEvents()
    }

    deinit {
        streamTask?.cancel()
        shellTask?.cancel()
        promptRecheckTask?.cancel()
    }

    func spawnTracked(_ operation: @escaping @MainActor () async -> Void) {
        taskExecutor.spawn(operation)
    }

    func spawnDetachedTracked(_ operation: @Sendable @escaping () async -> Void) {
        taskExecutor.spawnDetached(operation)
    }

    // MARK: - Public

    func send(_ text: String) {
        let eng = engine
        let processor = outputProcessor
        let sid = sessionID
        spawnTracked {
            await eng.send(text)
            await processor.accumulateInput(text, sessionID: sid)
        }
    }

    /// Detect agent type from a submitted command.
    func detectAgentFromCommand(_ command: String) {
        agentCoordinator.detectAgentFromCommand(
            command,
            sessionStore: sessionStore,
            sessionID: sessionID,
            taskExecutor: taskExecutor
        )
    }

    func resize(columns: UInt16, rows: UInt16) {
        let eng = engine
        spawnTracked { await eng.resize(columns: columns, rows: rows) }
    }

    // MARK: - Output subscription

    private func subscribeToOutput() {
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await event in engine.outputStream {
                guard !Task.isCancelled else { break }
                await handleOutputEvent(event)
            }
        }
    }

    private func handleOutputEvent(_ event: TerminalOutputEvent) async {
        switch event {
        case let .data(data):
            await handleDataOutput(data)

        case let .processExited(code):
            let sid = sessionID
            logger.info("Session \(sid) process exited code=\(code)")
            let detector = agentCoordinator.agentDetector
            let agentState = await detector.buildState()
            let session = sessionStore.sessions.first { $0.id == sessionID }
            let chunks = Array(outputProcessor.outputStore.chunks)
            sessionServices.generateHandoffIfNeeded(
                session: session,
                chunks: chunks,
                agentState: agentState,
                handoffService: sessionServices.sessionHandoffService,
                taskExecutor: taskExecutor
            )

        case let .titleChanged(title):
            sessionStore.renameSession(id: sessionID, title: title)

        case let .workingDirectoryChanged(path):
            sessionStore.updateWorkingDirectory(id: sessionID, path: path)
            await refreshMetadata(workingDirectory: path)
        }
    }

    private func handleDataOutput(_ data: Data) async {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let stripped = ANSIStripper.strip(text)
        let sid = sessionID
        let processor = outputProcessor
        let coordinator = agentCoordinator
        let tokenService = outputProcessor.tokenCountingService
        spawnDetachedTracked { [weak self] in
            await processor.processDataOutput(text, stripped: stripped, sessionID: sid)
            await coordinator.analyzeOutput(stripped, sessionID: sid, tokenCountingService: tokenService)
            await MainActor.run { @Sendable [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await agentCoordinator.updateAgentState(
                        tokenCountingService: outputProcessor.tokenCountingService,
                        sessionID: sessionID
                    )
                    await refreshMetadata()
                }
            }
        }
        detectPromptFromScreenBuffer()
        schedulePromptRecheck()
        await agentCoordinator.detectAgentFromOutput(stripped, sessionStore: sessionStore, sessionID: sid)
        await agentCoordinator.updateAgentState(
            tokenCountingService: outputProcessor.tokenCountingService,
            sessionID: sessionID
        )
        await refreshMetadata()
    }

    // MARK: - Shell events subscription

    private func subscribeToShellEvents() {
        shellTask = Task { [weak self] in
            guard let self else { return }
            for await event in engine.shellEventsStream {
                guard !Task.isCancelled else { break }
                await handleShellEvent(event)
            }
        }
    }

    private func handleShellEvent(_ event: ShellIntegrationEvent) async {
        switch event {
        case .promptStarted:
            isInteractivePrompt = false
            modeController.switchToEditor()
            sessionServices.injectContextIfNeeded(
                workingDirectory: currentMetadata.workingDirectory,
                engine: engine,
                clock: clock
            )
        case .executionFinished:
            isInteractivePrompt = false
            modeController.switchToEditor()
        case .executionStarted:
            isInteractivePrompt = false
            modeController.switchToPassthrough()
        case .commandStarted:
            break
        }

        if let chunk = await outputProcessor.handleShellEvent(event) {
            _ = chunk
            await refreshMetadata()
        }
    }

    // MARK: - Metadata

    func refreshMetadata(workingDirectory: String? = nil) async {
        let service = outputProcessor.tokenCountingService
        let sid = sessionID
        let breakdown = await service.tokenBreakdown(for: sid)
        let tokens = breakdown.totalTokens
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let cmdCount = outputProcessor.outputStore.chunks.count
        let dir = workingDirectory ?? currentMetadata.workingDirectory
        let agentDet = agentCoordinator.agentDetector
        let agentState = await agentDet.buildState()

        let ctxLimit = agentState?.contextWindowLimit ?? 0
        let ctxFraction = agentState?.contextUsageFraction ?? 0
        let agentElapsed = agentState.map {
            Date().timeIntervalSince($0.startedAt)
        } ?? 0
        let cost = agentState?.estimatedCostUSD ?? 0

        currentMetadata = SessionMetadata(
            sessionID: sessionID,
            estimatedTokenCount: tokens,
            totalCharacterCount: tokens * Int(AppConfig.AI.tokenEstimateDivisor),
            inputTokenCount: breakdown.inputTokens,
            outputTokenCount: breakdown.outputTokens,
            cachedTokenCount: breakdown.cachedTokens,
            estimatedCostUSD: cost,
            sessionDuration: elapsed,
            commandCount: cmdCount,
            workingDirectory: dir,
            activeAgentCount: agentCoordinator.agentStateStore?.activeAgentCount ?? 0,
            currentAgentType: agentState?.agentType,
            currentAgentStatus: agentState?.status,
            currentAgentTask: agentState?.currentTask,
            agentElapsedTime: agentElapsed,
            contextWindowLimit: ctxLimit,
            contextUsageFraction: ctxFraction,
            agentActiveFilePath: agentState?.activeFilePath
        )
    }
}
