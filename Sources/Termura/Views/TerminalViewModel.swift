import AppKit
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
    /// Internal (not private) so TerminalViewModel+PromptDetection.swift can access it;
    /// no external code outside the TerminalViewModel family should touch this.
    var promptRecheckTask: Task<Void, Never>?
    /// Throttled metadata refresh: independent slot from promptRecheckTask (CLAUDE.md §6 debounce rule).
    /// Internal so TerminalViewModel+Metadata.swift can manage the throttle lifecycle.
    var pendingMetadataRefreshTask: Task<Void, Never>?
    /// Timestamp of the last completed metadata refresh, used for throttle calculation.
    /// Internal so TerminalViewModel+Metadata.swift can update it after each refresh.
    var lastMetadataRefreshDate: Date = .distantPast
    /// Bounded executor for background tasks.
    private let taskExecutor: BoundedTaskExecutor
    private var streamTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?

    // MARK: - Agent resume

    /// Called at most once when the first shell prompt is detected in a restored session.
    /// Set by TerminalAreaView; nil-ed and guarded after first fire.
    var onShellPromptReadyForResume: (() -> Void)?
    private var hasTriggeredAgentResume = false

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
        agentCoordinator.onRiskAlertDetected = { [weak self] risk in
            // Only surface a new alert if none is already pending — prevents continuous
            // agent output from re-opening the sheet immediately after dismiss.
            guard self?.pendingRiskAlert == nil else { return }
            self?.pendingRiskAlert = risk
        }
        agentCoordinator.onContextWindowAlertDetected = { [weak self] alert in
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
                agentState: agentState
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

        // Debounced prompt check: schedulePromptRecheck already cancels-and-replaces,
        // so the immediate detectPromptFromScreenBuffer() call on every packet was redundant.
        schedulePromptRecheck()

        // Once the agent type is confirmed from output, skip further per-packet scanning.
        // bufferAndDetect is O(bufferLen) due to lowercased(); skipping saves that work entirely.
        if !coordinator.hasDetectedAgentFromOutput {
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
            // Single hop to main for all state writes + UI refresh (Principle 3).
            Task { @MainActor [weak self] in
                if let (state, alert) = update {
                    coordinator.applyAgentStateUpdate(state: state, alert: alert)
                }
                // Throttled: at most one SwiftUI refresh per metadataRefreshThrottleSeconds
                // during streaming. Shell events bypass this and call refreshMetadata() directly.
                self?.scheduleMetadataRefresh()
            }
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
        switch event {
        case .promptStarted:
            isInteractivePrompt = false
            modeController.switchToEditor()
            triggerAgentResumeIfNeeded()
            sessionServices.injectContextIfNeeded(
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
