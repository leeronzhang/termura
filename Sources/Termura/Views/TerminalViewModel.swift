import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalViewModel")

/// ViewModel bridging the terminal engine with output chunking, token counting,
/// and session metadata for the terminal area view hierarchy.
///
/// Delegates agent detection/state to `AgentCoordinator`, output chunking/tokens
/// to `OutputProcessor`, and context injection/handoff to `SessionServices`.
@Observable
@MainActor
final class TerminalViewModel {
    // MARK: - Observable state

    var currentMetadata: SessionMetadata
    /// True while an interactive tool (Claude Code `>`) is showing its prompt.
    var isInteractivePrompt: Bool = false
    /// Currently pending risk alert (shown as sheet).
    var pendingRiskAlert: RiskAlert?
    /// Context window warning alert (shown as sheet).
    var contextWindowAlert: ContextWindowAlert?

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

    // MARK: - Internal state (not view-driving — excluded from @Observable tracking)

    /// Debounced re-check for prompt detection after PTY output settles.
    /// Internal (not private) so TerminalViewModel+PromptDetection.swift can access it;
    /// no external code outside the TerminalViewModel family should touch this.
    @ObservationIgnored var promptRecheckTask: Task<Void, Never>?
    /// Throttled metadata refresh: independent slot from promptRecheckTask (CLAUDE.md §6 debounce rule).
    /// Internal so TerminalViewModel+Metadata.swift can manage the throttle lifecycle.
    @ObservationIgnored var pendingMetadataRefreshTask: Task<Void, Never>?
    /// Timestamp of the last completed metadata refresh, used for throttle calculation.
    /// Internal so TerminalViewModel+Metadata.swift can update it after each refresh.
    @ObservationIgnored var lastMetadataRefreshDate: Date = .distantPast
    /// Bounded executor for background tasks.
    private let taskExecutor: BoundedTaskExecutor
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var shellTask: Task<Void, Never>?

    // MARK: - Agent resume

    /// Called at most once when the first shell prompt is detected in a restored session.
    /// Set by TerminalAreaView; nil-ed and guarded after first fire.
    @ObservationIgnored var onShellPromptReadyForResume: (() -> Void)?
    @ObservationIgnored private var hasTriggeredAgentResume = false

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

        // Wire AgentCoordinator callbacks — coordinator detects, ViewModel owns the state.
        // Closures are @MainActor @Sendable: they run on the main actor (coordinator fires them
        // via Task { @MainActor in callback?(value) }) and capture @MainActor-isolated self safely.
        agentCoordinator.onRiskAlertDetected = { @MainActor [weak self] risk in
            // Only surface a new alert if none is already pending — prevents continuous
            // agent output from re-opening the sheet immediately after dismiss.
            guard self?.pendingRiskAlert == nil else { return }
            self?.pendingRiskAlert = risk
        }
        agentCoordinator.onContextWindowAlertDetected = { @MainActor [weak self] alert in
            self?.contextWindowAlert = alert
        }

        subscribeToOutput()
        subscribeToShellEvents()
    }

    deinit {
        streamTask?.cancel()
        shellTask?.cancel()
        promptRecheckTask?.cancel()
        pendingMetadataRefreshTask?.cancel()
    }

    func spawnTracked(_ operation: @escaping @MainActor () async -> Void) {
        taskExecutor.spawn(operation)
    }

    func spawnDetachedTracked(_ operation: @Sendable @escaping () async -> Void) {
        taskExecutor.spawnDetached(operation)
    }

    /// Fires `onShellPromptReadyForResume` exactly once per session lifecycle.
    /// Called from both OSC 133 (`promptStarted`) and screen-buffer fallback paths.
    func triggerAgentResumeIfNeeded() {
        guard !hasTriggeredAgentResume else { return }
        hasTriggeredAgentResume = true
        onShellPromptReadyForResume?()
        onShellPromptReadyForResume = nil
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
        let coordinator = agentCoordinator
        let store = sessionStore
        let sid = sessionID
        spawnTracked {
            await coordinator.detectAgentFromCommand(command, sessionStore: store, sessionID: sid)
        }
    }

    func resize(columns: UInt16, rows: UInt16) {
        let eng = engine
        spawnTracked { await eng.resize(columns: columns, rows: rows) }
    }

    /// Dismiss the pending risk alert. ViewModel is the single source of truth for alert state.
    func dismissRiskAlert() {
        pendingRiskAlert = nil
    }

    // MARK: - Output subscription

    private func subscribeToOutput() {
        // Task.detached: stream loop runs off @MainActor so UTF-8 decode + ANSI strip
        // do not block the main thread. Direct `await self?.method()` hops to MainActor
        // without allocating an intermediate Task on every event (CLAUDE.md Principle 3).
        let stream = engine.outputStream
        streamTask = Task.detached { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                switch event {
                case let .data(data):
                    // Pre-process off MainActor before hopping back.
                    guard let text = String(data: data, encoding: .utf8) else { continue }
                    let stripped = ANSIStripper.strip(text)
                    await self?.handlePreprocessedData(text: text, stripped: stripped)
                default:
                    await self?.handleOutputEvent(event)
                }
            }
        }
    }

    private func handleOutputEvent(_ event: TerminalOutputEvent) async {
        switch event {
        case .data:
            // Pre-processed in subscribeToOutput before the @MainActor hop.
            break

        case let .processExited(code):
            let sid = sessionID
            logger.info("Session \(sid) process exited code=\(code)")
            let detector = agentCoordinator.agentDetector
            let agentState = await detector.buildState()
            let session = sessionStore.sessions.first { $0.id == sessionID }
            let chunks = Array(outputProcessor.outputStore.chunks)
            await sessionServices.generateHandoffIfNeeded(
                session: session,
                chunks: chunks,
                agentState: agentState
            )

        case let .titleChanged(title):
            sessionStore.renameSession(id: sessionID, title: title)

        case let .workingDirectoryChanged(path):
            sessionStore.updateWorkingDirectory(id: sessionID, path: path)
            await refreshMetadata(workingDirectory: path)
        }
    }

    private func handlePreprocessedData(text: String, stripped: String) async {
        let sid = sessionID
        let processor = outputProcessor
        let coordinator = agentCoordinator
        let tokenService = outputProcessor.tokenCountingService

        // Debounced prompt check: schedulePromptRecheck already cancels-and-replaces,
        // so the immediate detectPromptFromScreenBuffer() call on every packet was redundant.
        schedulePromptRecheck()

        // Once the agent type is confirmed from output, skip further per-packet scanning.
        // bufferAndDetect is O(bufferLen) due to lowercased(); skipping saves that work entirely.
        if await !coordinator.hasDetectedAgentFromOutput {
            await coordinator.detectAgentFromOutput(stripped, sessionStore: sessionStore, sessionID: sid)
        }

        // Backpressure: during PTY floods (e.g. thousands of permission-error lines),
        // the task queue can accumulate faster than tasks complete. When at capacity,
        // drop this packet's background analysis — the token count and chunk detection
        // will be approximate, but the terminal rendering is unaffected and the UI stays responsive.
        guard !taskExecutor.isAtCapacity else { return }

        spawnDetachedTracked { [weak self] in
            await processor.processDataOutput(text, stripped: stripped, sessionID: sid)
            await coordinator.analyzeOutput(stripped, sessionID: sid, tokenCountingService: tokenService)
            let update = await coordinator.computeAgentStateUpdate(
                tokenCountingService: processor.tokenCountingService,
                sessionID: sid
            )
            if let (state, alert) = update {
                await coordinator.applyAgentStateUpdate(state: state, alert: alert)
            }
            // Single hop back to main for UI refresh (CLAUDE.md §6.1 Principle 3).
            Task { @MainActor [weak self] in self?.scheduleMetadataRefresh() }
        }
    }

    // MARK: - Shell events subscription

    private func subscribeToShellEvents() {
        // Task.detached: keeps stream iteration off @MainActor; direct await hops to
        // MainActor without allocating an intermediate Task on every event.
        let stream = engine.shellEventsStream
        shellTask = Task.detached { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.handleShellEvent(event)
            }
        }
    }

    private func handleShellEvent(_ event: ShellIntegrationEvent) async {
        switch event {
        case .promptStarted:
            isInteractivePrompt = false
            modeController.switchToEditor()
            triggerAgentResumeIfNeeded()
            await sessionServices.injectContextIfNeeded(
                workingDirectory: currentMetadata.workingDirectory,
                engine: engine,
                clock: clock
            )
        case .executionFinished:
            isInteractivePrompt = false
            modeController.switchToEditor()
            // Reset agent state so badges stop animating after the agent process exits.
            // Without this, repeatForever animations keep running, consuming ~80% CPU when idle.
            await agentCoordinator.resetOnExecutionFinished(sessionID: sessionID)
        case .executionStarted:
            isInteractivePrompt = false
            modeController.switchToPassthrough()
            detectAgentFromCurrentLine()
        case .commandStarted:
            break
        }

        if await outputProcessor.handleShellEvent(event) != nil {
            await refreshMetadata()
        }
    }
}
