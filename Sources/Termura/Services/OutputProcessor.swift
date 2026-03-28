import Foundation

/// Coordinates output chunking and token accumulation for a terminal session.
///
/// Owns `ChunkDetector`, `FallbackChunkDetector`, `OutputStore`, and
/// `TokenCountingServiceProtocol` — responsibilities extracted from
/// `TerminalViewModel` to reduce its init parameter count.
///
/// Not `@MainActor`: all stored dependencies are actors or `@MainActor`-isolated
/// types, so Swift enforces correct isolation automatically via `await`.
final class OutputProcessor: Sendable {
    // MARK: - Dependencies

    let outputStore: OutputStore
    let tokenCountingService: any TokenCountingServiceProtocol
    private let chunkDetector: ChunkDetector
    private let fallbackDetector: FallbackChunkDetector

    // MARK: - Init

    init(
        sessionID: SessionID,
        outputStore: OutputStore,
        tokenCountingService: any TokenCountingServiceProtocol
    ) {
        self.outputStore = outputStore
        self.tokenCountingService = tokenCountingService
        chunkDetector = ChunkDetector(sessionID: sessionID)
        fallbackDetector = FallbackChunkDetector(sessionID: sessionID)
    }

    // MARK: - Data output processing

    /// Process raw PTY data: append to chunk detector, run fallback chunk detection,
    /// and accumulate output tokens.
    ///
    /// Runs off the main actor. Each `await` hops to the appropriate actor
    /// (`ChunkDetector`, `FallbackChunkDetector`, `OutputStore`, `TokenCountingService`).
    func processDataOutput(
        _ text: String,
        stripped: String,
        sessionID: SessionID
    ) async {
        await chunkDetector.appendRawOutput(text)
        let chunks = await fallbackDetector.processOutput(stripped, raw: text)
        for chunk in chunks {
            await outputStore.append(chunk)
        }
        await tokenCountingService.accumulateOutput(for: sessionID, text: stripped)
    }

    // MARK: - Shell event handling

    /// Process a shell integration event through the chunk detector.
    /// Returns the completed chunk (if any) and appends it to the output store.
    func handleShellEvent(_ event: ShellIntegrationEvent) async -> OutputChunk? {
        guard let chunk = await chunkDetector.handleShellEvent(event) else { return nil }
        await outputStore.append(chunk)
        return chunk
    }

    // MARK: - Token accumulation

    /// Accumulate input tokens for the session.
    func accumulateInput(_ text: String, sessionID: SessionID) async {
        await tokenCountingService.accumulateInput(for: sessionID, text: text)
    }

    /// Accumulate cached token count for the session.
    func accumulateCached(_ count: Int, sessionID: SessionID) async {
        await tokenCountingService.accumulateCached(for: sessionID, count: count)
    }
}
