import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalSessionController")

/// Heavy-lifter for a terminal session: manages engine subscriptions, background tasks,
/// orchestration between services, and debounced metadata refreshes.
/// Offloads complexity from TerminalViewModel, which acts as the view's observable state holder.
@MainActor
final class TerminalSessionController {
    // MARK: - State & Tasks

    /// Bounded executor for background tasks.
    let taskExecutor: BoundedTaskExecutor
    @ObservationIgnored var streamTask: AutoCancellableTask?
    @ObservationIgnored var shellTask: AutoCancellableTask?
    @ObservationIgnored var processExitTask: AutoCancellableTask?
    @ObservationIgnored var hasTriggeredAgentResume = false
    @ObservationIgnored var agentDetectedFromOutput = false

    /// Specialized orchestrators to decouple responsibilities away from formatting God Object.
    let alertObserver: SessionAlertObserver
    let promptObserver: SessionPromptObserver
    let metadataObserver: SessionMetadataObserver
    /// Coalescing buffer for PTY output batches received while the executor is at capacity.
    /// Text and stripped strings are concatenated so the next drain pass processes all
    /// accumulated data without any silent drops. Guarded by @MainActor.
    @ObservationIgnored var pendingOutputBuffer: (text: String, stripped: String)?
    /// Drain watcher armed when PTY output is coalesced while the executor is saturated.
    /// This guarantees buffered output is retried even if the tasks freeing capacity are
    /// unrelated to output processing and therefore never call `drainPendingBufferIfNeeded()`.
    @ObservationIgnored var pendingOutputDrainTask: AutoCancellableTask?

    // MARK: - Dependencies

    let sessionID: SessionID
    let engine: any TerminalEngine
    let sessionStore: any SessionStoreProtocol
    let modeController: InputModeController
    let agentCoordinator: AgentCoordinator
    let outputProcessor: OutputProcessor
    let sessionServices: SessionServices
    let clock: any AppClock
    let notificationService: (any NotificationServiceProtocol)?
    weak var viewModel: TerminalViewModel?

    init(
        sessionID: SessionID,
        engine: any TerminalEngine,
        sessionStore: any SessionStoreProtocol,
        modeController: InputModeController,
        agentCoordinator: AgentCoordinator,
        outputProcessor: OutputProcessor,
        sessionServices: SessionServices,
        clock: any AppClock,
        notificationService: (any NotificationServiceProtocol)?,
        viewModel: TerminalViewModel? = nil
    ) {
        self.sessionID = sessionID
        self.engine = engine
        self.sessionStore = sessionStore
        self.modeController = modeController
        self.agentCoordinator = agentCoordinator
        self.outputProcessor = outputProcessor
        self.sessionServices = sessionServices
        self.clock = clock
        self.notificationService = notificationService
        self.viewModel = viewModel
        alertObserver = SessionAlertObserver(agentCoordinator: agentCoordinator, notificationService: notificationService)
        promptObserver = SessionPromptObserver(engine: engine, modeController: modeController, clock: clock)
        metadataObserver = SessionMetadataObserver(
            sessionID: sessionID,
            sessionStore: sessionStore,
            outputProcessor: outputProcessor,
            agentCoordinator: agentCoordinator,
            clock: clock
        )
        taskExecutor = BoundedTaskExecutor(maxConcurrent: AppConfig.Runtime.maxConcurrentSessionTasks)

        // Note: stream subscriptions are intentionally deferred to `inject(viewModel:)`.
        // If we subscribe here in init, incoming PTY/shell events can race and drop
        // state updates before the view model is fully attached on the next line.
    }

    func inject(viewModel: TerminalViewModel) {
        self.viewModel = viewModel
        alertObserver.inject(viewModel: viewModel)
        promptObserver.inject(viewModel: viewModel, controller: self)
        metadataObserver.inject(viewModel: viewModel)
        subscribeToOutput()
        subscribeToShellEvents()
    }

    func tearDown() {
        streamTask?.cancel()
        shellTask?.cancel()
        processExitTask?.cancel()
        promptObserver.tearDown()
        metadataObserver.tearDown()
        pendingOutputDrainTask?.cancel()
    }

    // MARK: - Subscriptions

    private func subscribeToShellEvents() {
        let stream = engine.shellEventsStream
        // WHY: Shell events arrive asynchronously from the terminal engine and must be consumed independently of the UI caller.
        // OWNER: TerminalSessionController owns shellTask.
        // TEARDOWN: deinit cancels shellTask and prompt/metadata teardown stops dependent observers.
        // TEST: Cover controller teardown while shell events are still streaming.
        shellTask = AutoCancellableTask(Task.detached { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                await handleShellEvent(event)
            }
        })
    }

    private func subscribeToOutput() {
        let stream = engine.outputStream
        // WHY: Terminal output can be continuous and must be drained in the background without blocking UI state updates.
        // OWNER: TerminalSessionController owns streamTask.
        // TEARDOWN: deinit cancels streamTask and pendingOutputDrainTask when the controller goes away.
        // TEST: Cover output delivery, cancellation, and teardown during active streaming.
        streamTask = AutoCancellableTask(Task.detached { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case let .data(data):
                    let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                    guard !text.isEmpty else { continue }
                    let stripped = ANSIStripper.strip(text)
                    await handlePreprocessedData(text: text, stripped: stripped)
                default:
                    await handleOutputEvent(event)
                }
            }
        })
    }

    // MARK: - Handlers

    private func handleShellEvent(_ event: ShellIntegrationEvent) async {
        switch event {
        case .promptStarted:
            viewModel?.isInteractivePrompt = false
            modeController.switchToEditor()
            triggerAgentResumeIfNeeded()
            await sessionServices.injectContextIfNeeded(
                workingDirectory: viewModel?.currentMetadata.workingDirectory ?? "",
                engine: engine,
                clock: clock
            )
        case .executionFinished:
            viewModel?.isInteractivePrompt = false
            modeController.switchToEditor()
            await agentCoordinator.resetOnExecutionFinished()
            agentDetectedFromOutput = false
            await outputProcessor.tokenCountingService.reset(for: sessionID)
        case .executionStarted:
            viewModel?.isInteractivePrompt = false
            modeController.switchToPassthrough()
            await detectAgentFromCurrentLine()
        case .commandStarted:
            break
        case .commandMetadata:
            // Metadata is forwarded to `outputProcessor.handleShellEvent` below;
            // no UI-level reaction is required.
            break
        }

        if await outputProcessor.handleShellEvent(event) != nil {
            await metadataObserver.refreshMetadata()
        }
    }

    private func handleOutputEvent(_ event: TerminalOutputEvent) async {
        switch event {
        case .data:
            break
        case let .processExited(code):
            processExitTask?.cancel()
            processExitTask = AutoCancellableTask(Task { [weak self] in
                await self?.finalizeProcessExit(code: code)
            })
        case let .titleChanged(title):
            sessionStore.renameSession(id: sessionID, title: title)
        case let .workingDirectoryChanged(path):
            sessionStore.updateWorkingDirectory(id: sessionID, path: path)
            await metadataObserver.refreshMetadata(workingDirectory: path)
        }
    }

    // MARK: - Orchestration Logic

    private func triggerAgentResumeIfNeeded() {
        guard !hasTriggeredAgentResume else { return }
        hasTriggeredAgentResume = true
        viewModel?.onShellPromptReadyForResume?()
        viewModel?.onShellPromptReadyForResume = nil
    }

    private func finalizeProcessExit(code: Int32) async {
        let sid = sessionID
        logger.info("Session \(sid) process exited code=\(code)")
        await waitForOutputProcessingIdle()
        let detector = agentCoordinator.agentDetector
        let agentState = await detector.buildState()
        let session = sessionStore.session(id: sid)
        let chunks = Array(outputProcessor.outputStore.chunks)
        await sessionServices.generateHandoffIfNeeded(
            session: session,
            chunks: chunks,
            agentState: agentState,
            projectRoot: sessionStore.projectRoot
        )
    }

    private func detectAgentFromCurrentLine() async {
        let screen = engine.linesNearCursor(above: 20)
        let lastLines = screen.suffix(2).joined()
        let stripped = ANSIStripper.strip(lastLines)
        if !agentDetectedFromOutput {
            agentDetectedFromOutput = await agentCoordinator.detectAgentFromOutputIfNeeded(stripped)
        }
    }

    // MARK: - Idle Condition

    /// Waits until the output coalescing buffer is fully drained and all executor tasks settle.
    /// Used before generating handoffs or taking final snapshots on process exit.
    func waitForOutputProcessingIdle() async {
        repeat {
            await taskExecutor.waitForIdle()
        } while pendingOutputBuffer != nil
        if let task = metadataObserver.pendingMetadataRefreshTask {
            await task.value
        }
        if let task = promptObserver.promptRecheckTask {
            await task.value
        }
        await sessionServices.flushPendingInjection()
    }
}
