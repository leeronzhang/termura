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
    let tokenCountingService: TokenCountingService

    // MARK: - Internal state

    let modeController: InputModeController
    private let chunkDetector: ChunkDetector
    private let fallbackDetector: FallbackChunkDetector
    let agentDetector: AgentStateDetector
    private let interventionService: InterventionService
    let contextWindowMonitor: ContextWindowMonitor
    weak var agentStateStore: AgentStateStore?
    let sessionStartTime: Date = .init()
    private var streamTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?
    /// Debounced re-check for prompt detection after PTY output settles.
    var promptRecheckTask: Task<Void, Never>?

    // MARK: - Context injection & handoff

    private let isRestoredSession: Bool
    private let contextInjectionService: ContextInjectionService?
    let sessionHandoffService: SessionHandoffService?
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
        tokenCountingService: TokenCountingService,
        modeController: InputModeController,
        agentStateStore: AgentStateStore? = nil,
        isRestoredSession: Bool = false,
        contextInjectionService: ContextInjectionService? = nil,
        sessionHandoffService: SessionHandoffService? = nil
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
        chunkDetector = ChunkDetector(sessionID: sessionID)
        fallbackDetector = FallbackChunkDetector(sessionID: sessionID)
        agentDetector = AgentStateDetector(sessionID: sessionID)
        interventionService = InterventionService()
        contextWindowMonitor = ContextWindowMonitor()

        let workingDir = FileManager.default.homeDirectoryForCurrentUser.path
        currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: workingDir
        )

        subscribeToOutput()
        subscribeToShellEvents()
    }

    deinit {
        streamTask?.cancel()
        shellTask?.cancel()
        promptRecheckTask?.cancel()
    }

    // MARK: - Public

    func send(_ text: String) {
        Task { await engine.send(text) }
    }

    func resize(columns: UInt16, rows: UInt16) {
        Task { await engine.resize(columns: columns, rows: rows) }
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
            guard let text = String(data: data, encoding: .utf8) else { return }
            let stripped = ANSIStripper.strip(text)
            let sid = sessionID
            let detector = chunkDetector
            let fallback = fallbackDetector
            let store = outputStore
            let service = tokenCountingService
            let agentDet = agentDetector
            let intervention = interventionService
            Task.detached {
                await detector.appendRawOutput(text)
                let chunks = await fallback.processOutput(stripped, raw: text)
                await MainActor.run {
                    for chunk in chunks {
                        store.append(chunk)
                    }
                }
                await service.accumulate(for: sid, text: stripped)
                // Agent status analysis
                _ = await agentDet.analyzeOutput(stripped)
                // Risk detection
                if let risk = await intervention.detectRisk(in: stripped) {
                    await MainActor.run { [weak self] in
                        self?.pendingRiskAlert = risk
                    }
                }
            }
            detectPromptFromScreenBuffer()
            schedulePromptRecheck()
            await updateAgentState()
            await refreshMetadata()

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

    // MARK: - Context injection

    func injectContextIfNeeded() {
        guard isRestoredSession, !hasInjectedContext else { return }
        hasInjectedContext = true
        let workingDir = currentMetadata.workingDirectory
        guard !workingDir.isEmpty else { return }
        guard let service = contextInjectionService else { return }
        Task { @MainActor [weak self] in
            guard let text = await service.buildInjectionText(projectRoot: workingDir) else { return }
            do {
                try await Task.sleep(nanoseconds: AppConfig.SessionHandoff.injectionDelayNanoseconds)
            } catch is CancellationError {
                return
            } catch {
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
