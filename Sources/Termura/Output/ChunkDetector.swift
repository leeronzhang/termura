import Foundation

/// Actor that transforms a stream of raw PTY output + shell integration events
/// into structured `OutputChunk` values.
///
/// Call `appendRawOutput(_:)` for every terminal data event.
/// Call `handleShellEvent(_:)` for every OSC 133 event.
/// Returns a finished chunk when `executionFinished` is received.
actor ChunkDetector {
    // MARK: - State

    private var state: ShellIntegrationState = .init()
    private var pendingOutput: String = ""
    private var pendingRawANSI: String = ""
    private let sessionID: SessionID
    private let clock: any AppClock

    // MARK: - Init

    init(sessionID: SessionID, clock: any AppClock = LiveClock()) {
        self.sessionID = sessionID
        self.clock = clock
    }

    // MARK: - Public API

    /// Append raw PTY text (may contain ANSI escapes).
    /// Stores both ANSI-stripped and raw versions, capped at `AppConfig.Output.maxChunkOutputChars`.
    func appendRawOutput(_ text: String) {
        let stripped = ANSIStripper.strip(text)
        appendToPending(stripped: stripped, raw: text)
    }

    /// Process a shell integration event, potentially completing a chunk.
    /// Returns a finished `OutputChunk` when `executionFinished` is received, nil otherwise.
    func handleShellEvent(_ event: ShellIntegrationEvent) -> OutputChunk? {
        let previousPhase = state.phase
        state.apply(event, now: clock.now())

        if case let .executionFinished(exitCode) = event {
            let metadata = state.consumePendingMetadata()
            return buildChunk(from: previousPhase, exitCode: exitCode, metadata: metadata)
        }
        return nil
    }

    /// Discard any buffered output and reset integration state.
    /// Use when a session restarts and stale pending content must not bleed into the next chunk.
    func reset() {
        pendingOutput = ""
        pendingRawANSI = ""
        state = .init()
    }

    // MARK: - Private

    private func appendToPending(stripped: String, raw: String) {
        let remaining = AppConfig.Output.maxChunkOutputChars - pendingOutput.count
        guard remaining > 0 else { return }

        if stripped.count <= remaining {
            pendingOutput += stripped
            pendingRawANSI += raw
        } else {
            pendingOutput += stripped.prefix(remaining)
            pendingOutput += "\n\u{2026}[truncated]"
            pendingRawANSI += raw.prefix(remaining)
        }
    }

    private func buildChunk(
        from phase: ShellIntegrationPhase,
        exitCode: Int?,
        metadata: [String: String]
    ) -> OutputChunk? {
        let command: String
        let startedAt: Date

        switch phase {
        case let .executing(cmd, start):
            command = cmd
            startedAt = start
        case let .commandInput(cmd):
            command = cmd
            startedAt = clock.now()
        default:
            // No executing phase tracked — skip building chunk
            let capturedOutput = pendingOutput
            let capturedRaw = pendingRawANSI
            pendingOutput = ""
            pendingRawANSI = ""
            guard !capturedOutput.isEmpty else { return nil }
            return makeChunk(ChunkInput(
                command: "",
                output: capturedOutput,
                raw: capturedRaw,
                startedAt: clock.now(),
                exitCode: exitCode,
                metadata: metadata
            ))
        }

        let capturedOutput = pendingOutput
        let capturedRaw = pendingRawANSI
        pendingOutput = ""
        pendingRawANSI = ""

        return makeChunk(ChunkInput(
            command: command,
            output: capturedOutput,
            raw: capturedRaw,
            startedAt: startedAt,
            exitCode: exitCode,
            metadata: metadata
        ))
    }

    private struct ChunkInput {
        let command: String
        let output: String
        let raw: String
        let startedAt: Date
        let exitCode: Int?
        let metadata: [String: String]
    }

    private func makeChunk(_ input: ChunkInput) -> OutputChunk {
        let lines = input.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let classification = SemanticParser.classify(lines, command: input.command)
        let uiBlock = SemanticParser.buildUIContent(
            from: classification,
            displayLines: lines,
            exitCode: input.exitCode
        )
        return OutputChunk(
            sessionID: sessionID,
            commandText: input.command,
            outputLines: lines,
            rawANSI: input.raw,
            exitCode: input.exitCode,
            startedAt: input.startedAt,
            finishedAt: clock.now(),
            contentType: classification.type,
            uiContent: uiBlock,
            metadata: input.metadata
        )
    }
}
