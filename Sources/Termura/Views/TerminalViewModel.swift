import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalViewModel")

/// ViewModel bridging the terminal engine with output chunking, token counting,
/// and session metadata for the terminal area view hierarchy.
@MainActor
final class TerminalViewModel: ObservableObject {
    // MARK: - Published state

    @Published var currentMetadata: SessionMetadata
    /// True while an interactive tool (Claude Code `>`) is showing its prompt.
    /// Drives the overlay layout: EditorInputView floats over the terminal bottom,
    /// visually covering the tool's own cursor line.
    @Published var isInteractivePrompt: Bool = false

    // MARK: - Dependencies

    let sessionID: SessionID
    let engine: any TerminalEngine
    let sessionStore: any SessionStoreProtocol
    let outputStore: OutputStore
    let tokenCountingService: any TokenCountingServiceProtocol

    // MARK: - Internal state

    let modeController: InputModeController
    private let chunkDetector: ChunkDetector
    private let fallbackDetector: FallbackChunkDetector
    let agentDetector: AgentStateDetector
    private let interventionService: InterventionService
    let contextWindowMonitor: ContextWindowMonitor
    let clock: any AppClock
    weak var agentStateStore: AgentStateStore? // concrete: weak requires class type
    let sessionStartTime: Date = .init()
    /// Prevents repeated renames after the agent is already detected from output.
    var hasDetectedAgentFromOutput = false
    /// Tracks the last detected agent type so we can re-detect when a different agent starts.
    var lastDetectedAgentType: AgentType?
    private var streamTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?
    /// Debounced re-check for prompt detection after PTY output settles.
    var promptRecheckTask: Task<Void, Never>?
    /// Bounded executor for background tasks — limits concurrent execution
    /// and auto-cleans completed tasks to prevent unbounded accumulation.
    private let taskExecutor: BoundedTaskExecutor
    /// Context injection task — stored separately because it uses a sleep delay.
    private var injectionTask: Task<Void, Never>?

    // MARK: - Context injection & handoff

    private let isRestoredSession: Bool
    private let contextInjectionService: (any ContextInjectionServiceProtocol)?
    let sessionHandoffService: (any SessionHandoffServiceProtocol)?
    private var hasInjectedContext = false

    /// Currently pending risk alert (shown as sheet).
    @Published var pendingRiskAlert: RiskAlert?
    /// Context window warning alert (shown as sheet).
    @Published var contextWindowAlert: ContextWindowAlert?

    // MARK: - Init

    init(
        sessionID: SessionID,
        engine: any TerminalEngine,
        sessionStore: any SessionStoreProtocol,
        outputStore: OutputStore,
        tokenCountingService: any TokenCountingServiceProtocol,
        modeController: InputModeController,
        agentStateStore: AgentStateStore? = nil,
        isRestoredSession: Bool = false,
        contextInjectionService: (any ContextInjectionServiceProtocol)? = nil,
        sessionHandoffService: (any SessionHandoffServiceProtocol)? = nil,
        clock: any AppClock = LiveClock()
    ) {
        self.sessionID = sessionID
        self.engine = engine
        self.sessionStore = sessionStore
        self.outputStore = outputStore
        self.tokenCountingService = tokenCountingService
        self.modeController = modeController
        self.agentStateStore = agentStateStore
        self.isRestoredSession = isRestoredSession
        self.contextInjectionService = contextInjectionService
        self.sessionHandoffService = sessionHandoffService
        self.clock = clock
        taskExecutor = BoundedTaskExecutor(maxConcurrent: AppConfig.Runtime.maxConcurrentSessionTasks)
        chunkDetector = ChunkDetector(sessionID: sessionID)
        fallbackDetector = FallbackChunkDetector(sessionID: sessionID)
        agentDetector = AgentStateDetector(sessionID: sessionID)
        interventionService = InterventionService()
        contextWindowMonitor = ContextWindowMonitor()

        let workingDir = AppConfig.Paths.homeDirectory
        currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: workingDir
        )

        subscribeToOutput()
        subscribeToShellEvents()
    }

    // Safe: SE-0371 allows deinit to access stored properties (exclusive ownership).
    deinit {
        streamTask?.cancel()
        shellTask?.cancel()
        promptRecheckTask?.cancel()
        injectionTask?.cancel()
        // taskExecutor cancels all tracked tasks in its own deinit.
    }

    /// Spawns a background task inheriting the current actor context with bounded concurrency.
    /// Use for fire-and-forget work that accesses non-Sendable dependencies (engine, sessionStore).
    func spawnTracked(_ operation: @escaping @MainActor () async -> Void) {
        taskExecutor.spawn(operation)
    }

    /// Spawns a detached background task with bounded concurrency.
    /// Use for heavy processing that must run off MainActor.
    func spawnDetachedTracked(
        _ operation: @Sendable @escaping () async -> Void
    ) {
        taskExecutor.spawnDetached(operation)
    }

    // MARK: - Public

    func send(_ text: String) {
        let eng = engine
        let service = tokenCountingService
        let sid = sessionID
        spawnTracked {
            await eng.send(text)
            await service.accumulateInput(for: sid, text: text)
        }
    }

    /// Detect agent type from a submitted command and update session/agent state if matched.
    func detectAgentFromCommand(_ command: String) {
        let detector = agentDetector
        let store = sessionStore
        let sid = sessionID
        let stateStore = agentStateStore
        spawnTracked {
            guard let agentType = await detector.detectFromCommand(command) else { return }
            let agentState = await detector.buildState()
            // Already on MainActor via spawnTracked — no need for MainActor.run.
            store.renameSession(id: sid, title: agentType.displayName)
            store.setAgentType(id: sid, type: agentType)
            if let state = agentState {
                stateStore?.update(state: state)
            }
        }
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
            await generateHandoffIfNeeded(exitCode: code)

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
        let detector = chunkDetector
        let fallback = fallbackDetector
        let store = outputStore
        let service = tokenCountingService
        let agentDet = agentDetector
        let intervention = interventionService
        spawnDetachedTracked { [weak self] in
            await detector.appendRawOutput(text)
            let chunks = await fallback.processOutput(stripped, raw: text)
            await MainActor.run {
                for chunk in chunks {
                    store.append(chunk)
                }
            }
            await service.accumulateOutput(for: sid, text: stripped)
            _ = await agentDet.analyzeOutput(stripped)
            if let stats = await agentDet.parseTokenStats(stripped) {
                if let cached = stats.cachedTokens, cached > 0 {
                    await service.accumulateCached(for: sid, count: cached)
                }
                if let cost = stats.totalCost {
                    await agentDet.updateCost(cost)
                }
            }
            if let risk = await intervention.detectRisk(in: stripped) {
                await MainActor.run {
                    self?.pendingRiskAlert = risk
                }
            }
        }
        detectPromptFromScreenBuffer()
        schedulePromptRecheck()
        detectAgentFromOutput(stripped)
        await updateAgentState()
        await refreshMetadata()
    }

    // MARK: - Context injection

    func injectContextIfNeeded() {
        guard isRestoredSession, !hasInjectedContext else { return }
        hasInjectedContext = true
        let workingDir = currentMetadata.workingDirectory
        guard !workingDir.isEmpty else { return }
        guard let service = contextInjectionService else { return }
        injectionTask?.cancel()
        injectionTask = Task { @MainActor [weak self] in
            guard let text = await service.buildInjectionText(projectRoot: workingDir) else { return }
            do {
                try await self?.clock.sleep(for: .nanoseconds(AppConfig.SessionHandoff.injectionDelayNanoseconds))
            } catch is CancellationError {
                return
            } catch {
                // Non-critical: context injection is supplementary; session functions without it.
                logger.warning("Context injection delay failed: \(error.localizedDescription)")
                return
            }
            await self?.engine.send(text)
        }
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
        // Drive editor visibility: show input at prompt, hide while executing.
        switch event {
        case .promptStarted:
            isInteractivePrompt = false
            modeController.switchToEditor()
            injectContextIfNeeded()
        case .executionFinished:
            isInteractivePrompt = false
            modeController.switchToEditor()
        case .executionStarted:
            isInteractivePrompt = false
            modeController.switchToPassthrough()
        case .commandStarted:
            break
        }

        let detector = chunkDetector
        guard let chunk = await detector.handleShellEvent(event) else { return }
        outputStore.append(chunk)
        await refreshMetadata()
    }
}
