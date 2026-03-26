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
    weak var agentStateStore: AgentStateStore? // concrete: weak requires class type
    let sessionStartTime: Date = .init()
    /// Prevents repeated renames after the agent is already detected from output.
    private var hasDetectedAgentFromOutput = false
    private var streamTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?
    /// Debounced re-check for prompt detection after PTY output settles.
    var promptRecheckTask: Task<Void, Never>?

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
        sessionHandoffService: (any SessionHandoffServiceProtocol)? = nil
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

        let workingDir = AppConfig.Paths.homeDirectory
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

    /// Detect agent type from a submitted command and update session title if matched.
    func detectAgentFromCommand(_ command: String) {
        let detector = agentDetector
        let store = sessionStore
        let sid = sessionID
        Task {
            guard let agentType = await detector.detectFromCommand(command) else { return }
            await MainActor.run {
                store.renameSession(id: sid, title: agentType.displayName)
            }
        }
    }

    // MARK: - Output-based agent detection

    /// Signature patterns in terminal output that identify a running agent.
    private static let outputSignatures: [(pattern: String, type: AgentType)] = [
        ("claude code", .claudeCode),
        ("anthropic", .claudeCode),
        ("openai codex", .codex),
        (">_ openai codex", .codex),
        ("aider v", .aider),
        ("opencode", .openCode),
        ("gemini cli", .gemini),
        ("gemini code", .gemini)
    ]

    /// Strips known agent icon prefixes from OSC terminal titles (e.g. "\u{2733} Claude Code" -> "Claude Code").
    static func stripAgentPrefixes(_ title: String) -> String {
        var stripped = title.trimmingCharacters(in: .whitespaces)
        // Known prefixes set by AI tools via OSC title
        let prefixes = ["\u{2733}", ">_", "\u{2726}", "\u{26A1}", "\u{203A}"]
        for prefix in prefixes where stripped.hasPrefix(prefix) {
            stripped = String(stripped.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return stripped.isEmpty ? title : stripped
    }

    /// Scan terminal output for agent signatures and rename the session on first match.
    private func detectAgentFromOutput(_ text: String) {
        guard !hasDetectedAgentFromOutput else { return }
        let lower = text.lowercased()
        for (pattern, type) in Self.outputSignatures where lower.contains(pattern) {
            hasDetectedAgentFromOutput = true
            sessionStore.renameSession(id: sessionID, title: type.displayName)
            sessionStore.setAgentType(id: sessionID, type: type)
            return
        }
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
            await handleDataOutput(data)

        case let .processExited(code):
            let sid = sessionID
            logger.info("Session \(sid) process exited code=\(code)")
            await generateHandoffIfNeeded(exitCode: code)

        case let .titleChanged(title):
            if !hasDetectedAgentFromOutput {
                sessionStore.renameSession(id: sessionID, title: Self.stripAgentPrefixes(title))
            }

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
        Task.detached {
            await detector.appendRawOutput(text)
            let chunks = await fallback.processOutput(stripped, raw: text)
            await MainActor.run {
                for chunk in chunks {
                    store.append(chunk)
                }
            }
            await service.accumulate(for: sid, text: stripped)
            _ = await agentDet.analyzeOutput(stripped)
            if let risk = await intervention.detectRisk(in: stripped) {
                await MainActor.run { [weak self] in
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
