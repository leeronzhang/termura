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
    private let sessionStartTime: Date = Date()
    private var streamTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?

    // MARK: - Init

    init(
        sessionID: SessionID,
        engine: any TerminalEngine,
        sessionStore: any SessionStoreProtocol,
        outputStore: OutputStore,
        tokenCountingService: TokenCountingService,
        modeController: InputModeController
    ) {
        self.sessionID = sessionID
        self.engine = engine
        self.sessionStore = sessionStore
        self.outputStore = outputStore
        self.tokenCountingService = tokenCountingService
        self.modeController = modeController
        self.chunkDetector = ChunkDetector(sessionID: sessionID)
        self.fallbackDetector = FallbackChunkDetector(sessionID: sessionID)

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
            Task.detached {
                await detector.appendRawOutput(text)
                // Always run fallback: detects AI tool prompts (^>$) regardless of OSC 133 state.
                // The aiToolPromptPattern only matches Claude Code's `>` line and does not overlap
                // with OSC 133 shell events, so there is no risk of duplicate chunks.
                let chunks = await fallback.processOutput(stripped, raw: text)
                await MainActor.run {
                    for chunk in chunks { store.append(chunk) }
                }
                await service.accumulate(for: sid, text: stripped)
            }
            // Prompt detection via SwiftTerm screen buffer — reliable for TUI apps.
            // Claude Code uses ANSI cursor-movement to render its `>` prompt, so the
            // raw byte stream cannot be split on \n to find it.  Reading the rendered
            // cursor row from SwiftTerm's buffer always gives the correct text.
            detectPromptFromScreenBuffer()
            await refreshMetadata()

        case .processExited(let code):
            let sid = sessionID
            logger.info("Session \(sid) process exited code=\(code)")

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
    private func detectPromptFromScreenBuffer() {
        let cursorLine = engine.cursorLineContent()?.trimmingCharacters(in: .whitespaces) ?? ""

        if cursorLine == ">" {
            // Claude Code (or other AI tool) is waiting for input.
            isInteractivePrompt = true
            modeController.switchToEditor()
        } else if cursorLine.hasSuffix(" $") || cursorLine.hasSuffix(" %")
                    || cursorLine.hasSuffix(" #") || cursorLine == "$"
                    || cursorLine == "%" || cursorLine == "#" {
            // Back at shell prompt.
            isInteractivePrompt = false
            if modeController.mode == .passthrough { modeController.switchToEditor() }
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
        case .promptStarted, .executionFinished:
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

    // MARK: - Metadata

    private func refreshMetadata(workingDirectory: String? = nil) async {
        let service = tokenCountingService
        let sid = sessionID
        let tokens = await service.estimatedTokens(for: sid)
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let cmdCount = outputStore.chunks.count
        let dir = workingDirectory ?? currentMetadata.workingDirectory

        currentMetadata = SessionMetadata(
            sessionID: sessionID,
            estimatedTokenCount: tokens,
            totalCharacterCount: tokens * Int(AppConfig.AI.tokenEstimateDivisor),
            sessionDuration: elapsed,
            commandCount: cmdCount,
            workingDirectory: dir
        )
    }
}
