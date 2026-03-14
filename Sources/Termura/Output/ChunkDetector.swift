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

    // MARK: - Init

    init(sessionID: SessionID) {
        self.sessionID = sessionID
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
        state.apply(event)

        if case .executionFinished(let exitCode) = event {
            return buildChunk(from: previousPhase, exitCode: exitCode)
        }
        return nil
    }

    /// Clear all pending buffers and reset FSM to idle.
    func reset() {
        state = ShellIntegrationState()
        pendingOutput = ""
        pendingRawANSI = ""
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
            pendingOutput += "\n…[truncated]"
            pendingRawANSI += raw.prefix(remaining)
        }
    }

    private func buildChunk(from phase: ShellIntegrationPhase, exitCode: Int?) -> OutputChunk? {
        let command: String
        let startedAt: Date

        switch phase {
        case .executing(let cmd, let start):
            command = cmd
            startedAt = start
        case .commandInput(let cmd):
            command = cmd
            startedAt = Date()
        default:
            // No executing phase tracked — skip building chunk
            let capturedOutput = pendingOutput
            let capturedRaw = pendingRawANSI
            pendingOutput = ""
            pendingRawANSI = ""
            guard !capturedOutput.isEmpty else { return nil }
            return makeChunk(
                command: "",
                output: capturedOutput,
                raw: capturedRaw,
                startedAt: Date(),
                exitCode: exitCode
            )
        }

        let capturedOutput = pendingOutput
        let capturedRaw = pendingRawANSI
        pendingOutput = ""
        pendingRawANSI = ""

        return makeChunk(
            command: command,
            output: capturedOutput,
            raw: capturedRaw,
            startedAt: startedAt,
            exitCode: exitCode
        )
    }

    private func makeChunk(
        command: String,
        output: String,
        raw: String,
        startedAt: Date,
        exitCode: Int?
    ) -> OutputChunk {
        let lines = output.components(separatedBy: "\n")
        return OutputChunk(
            sessionID: sessionID,
            commandText: command,
            outputLines: lines,
            rawANSI: raw,
            exitCode: exitCode,
            startedAt: startedAt,
            finishedAt: Date()
        )
    }
}
