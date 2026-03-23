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
    @Published private(set) var isInteractivePrompt: Bool = false

    // MARK: - Dependencies

    private let sessionID: SessionID
    private let engine: any TerminalEngine
    private let sessionStore: any SessionStoreProtocol
    private let outputStore: OutputStore
    private let tokenCountingService: TokenCountingService

    // MARK: - Internal state

    private let modeController: InputModeController
    private let chunkDetector: ChunkDetector
    private let fallbackDetector: FallbackChunkDetector
    private let agentDetector: AgentStateDetector
    private let interventionService: InterventionService
    private weak var agentStateStore: AgentStateStore?
    private let sessionStartTime: Date = Date()
    private var streamTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?
    /// Debounced re-check for prompt detection after PTY output settles.
    private var promptRecheckTask: Task<Void, Never>?

    // MARK: - Context injection

    private let isRestoredSession: Bool
    private let contextInjectionService: ContextInjectionService?
    private var hasInjectedContext = false

    /// Currently pending risk alert (shown as sheet).
    @Published var pendingRiskAlert: RiskAlert?

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
        contextInjectionService: ContextInjectionService? = nil
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
        self.chunkDetector = ChunkDetector(sessionID: sessionID)
        self.fallbackDetector = FallbackChunkDetector(sessionID: sessionID)
        self.agentDetector = AgentStateDetector(sessionID: sessionID)
        self.interventionService = InterventionService()

        let workingDir = FileManager.default.homeDirectoryForCurrentUser.path
        self.currentMetadata = SessionMetadata.empty(
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
        case .data(let data):
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
                    for chunk in chunks { store.append(chunk) }
                }
                await service.accumulate(for: sid, text: stripped)
                // Agent status analysis
                let _ = await agentDet.analyzeOutput(stripped)
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

        case .processExited(let code):
            let sid = sessionID
            logger.info("Session \(sid) process exited code=\(code)")
            await generateHandoffIfNeeded(exitCode: code)

        case .titleChanged(let title):
            sessionStore.renameSession(id: sessionID, title: title)

        case .workingDirectoryChanged(let path):
            sessionStore.updateWorkingDirectory(id: sessionID, path: path)
            await refreshMetadata(workingDirectory: path)
        }
    }

    // MARK: - Prompt detection via screen buffer

    /// Reads the rendered cursor row from SwiftTerm's screen buffer to determine
    /// which kind of prompt (if any) is currently displayed.
    ///
    /// Why screen buffer instead of raw bytes:
    ///   TUI apps like Claude Code use ANSI cursor-movement sequences to position
    ///   text.  The raw PTY stream cannot be reliably split on newlines to find the
    ///   `>` prompt — it appears embedded in a dense block of escape codes.
    ///   After `super.dataReceived(slice:)` runs, SwiftTerm's buffer holds the
    ///   *rendered* state; `getLine(row: cursorRow)` returns exactly what is shown.
    /// Characters used as AI tool prompts (Claude Code, Aider, etc.).
    /// `>` (U+003E), `❯` (U+276F), and `›` (U+203A) are all common.
    private static let aiPromptCharacters: Set<Character> = [">", "\u{276F}", "\u{203A}"]

    private func detectPromptFromScreenBuffer() {
        // Scan cursor line + up to 5 lines above. TUI apps (Claude Code) often
        // position the cursor on hint/status lines below the actual prompt.
        let lines = engine.linesNearCursor(above: 5)

        #if DEBUG
        if modeController.mode == .passthrough {
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let codepoints = trimmed.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                logger.debug("promptDetect[\(i)]: '\(trimmed)' codepoints=[\(codepoints)]")
            }
        }
        #endif

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isAIPromptLine(trimmed) {
                isInteractivePrompt = true
                modeController.switchToEditor()
                injectContextIfNeeded()
                return
            }
        }

        // Fall back: check cursor line for shell prompt.
        let cursorLine = lines.last?.trimmingCharacters(in: .whitespaces) ?? ""
        if isShellPromptLine(cursorLine) {
            isInteractivePrompt = false
            if modeController.mode == .passthrough {
                modeController.switchToEditor()
                injectContextIfNeeded()
            }
        }
    }

    private func isShellPromptLine(_ line: String) -> Bool {
        line.hasSuffix(" $") || line.hasSuffix(" %")
            || line.hasSuffix(" #") || line == "$"
            || line == "%" || line == "#"
    }

    /// Returns true if the line is an AI tool prompt: a single prompt character
    /// optionally followed by whitespace. Handles `>`, `❯`, `›` and variations.
    private func isAIPromptLine(_ line: String) -> Bool {
        guard let first = line.first, Self.aiPromptCharacters.contains(first) else {
            return false
        }
        // The rest (after the prompt character) must be empty or whitespace-only.
        let rest = line.dropFirst()
        return rest.allSatisfy(\.isWhitespace)
    }

    /// Schedules a debounced re-check of the screen buffer after PTY output settles.
    /// Solves the race where prompt characters arrive across multiple data chunks —
    /// the immediate `detectPromptFromScreenBuffer()` may fire before SwiftTerm has
    /// rendered the full prompt line, and no further data event triggers a re-check.
    private func schedulePromptRecheck() {
        promptRecheckTask?.cancel()
        promptRecheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            guard !Task.isCancelled else { return }
            self?.detectPromptFromScreenBuffer()
        }
    }

    // MARK: - Context injection

    private func injectContextIfNeeded() {
        guard isRestoredSession, !hasInjectedContext else { return }
        hasInjectedContext = true
        let workingDir = currentMetadata.workingDirectory
        guard !workingDir.isEmpty else { return }
        guard let service = contextInjectionService else { return }
        Task { @MainActor [weak self] in
            guard let text = await service.buildInjectionText(projectRoot: workingDir) else { return }
            try? await Task.sleep(nanoseconds: AppConfig.SessionHandoff.injectionDelayNanoseconds)
            guard !Task.isCancelled else { return }
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

    // MARK: - Session Handoff

    private func generateHandoffIfNeeded(exitCode: Int32) async {
        let agentDet = agentDetector
        guard let agentState = await agentDet.buildState(),
              agentState.agentType != .unknown else { return }

        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }),
              !session.workingDirectory.isEmpty else { return }

        let chunks = outputStore.chunks

        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let handoffService = appDelegate.sessionHandoffService

        Task.detached {
            do {
                try await handoffService.generateHandoff(
                    session: session,
                    chunks: chunks,
                    agentState: agentState
                )
            } catch {
                logger.error("Session handoff failed: \(error)")
            }
        }
    }

    // MARK: - Agent State

    private func updateAgentState() async {
        let agentDet = agentDetector
        guard let state = await agentDet.buildState() else { return }
        agentStateStore?.update(state: state)
    }

    // MARK: - Metadata

    private func refreshMetadata(workingDirectory: String? = nil) async {
        let service = tokenCountingService
        let sid = sessionID
        let tokens = await service.estimatedTokens(for: sid)
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let cmdCount = outputStore.chunks.count
        let dir = workingDirectory ?? currentMetadata.workingDirectory
        let agentDet = agentDetector
        let agentState = await agentDet.buildState()

        currentMetadata = SessionMetadata(
            sessionID: sessionID,
            estimatedTokenCount: tokens,
            totalCharacterCount: tokens * Int(AppConfig.AI.tokenEstimateDivisor),
            sessionDuration: elapsed,
            commandCount: cmdCount,
            workingDirectory: dir,
            activeAgentCount: agentStateStore?.activeAgentCount ?? 0,
            currentAgentType: agentState?.agentType,
            currentAgentStatus: agentState?.status
        )
    }
}
