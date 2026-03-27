import Foundation

/// Coordinates output chunking and token accumulation for a terminal session.
///
/// Owns `ChunkDetector`, `FallbackChunkDetector`, `OutputStore`, and
/// `TokenCountingServiceProtocol` — responsibilities extracted from
/// `TerminalViewModel` to reduce its init parameter count.
@MainActor
final class OutputProcessor {
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
    func processDataOutput(
        _ text: String,
        stripped: String,
        sessionID: SessionID
    ) async {
        let detector = chunkDetector
        let fallback = fallbackDetector
        let store = outputStore
        let service = tokenCountingService

        await detector.appendRawOutput(text)
        let chunks = await fallback.processOutput(stripped, raw: text)
        await MainActor.run {
            for chunk in chunks {
                store.append(chunk)
            }
        }
        await service.accumulateOutput(for: sessionID, text: stripped)
    }

    // MARK: - Shell event handling

    /// Process a shell integration event through the chunk detector.
    /// Returns the completed chunk (if any) and appends it to the output store.
    func handleShellEvent(_ event: ShellIntegrationEvent) async -> OutputChunk? {
        let detector = chunkDetector
        guard let chunk = await detector.handleShellEvent(event) else { return nil }
        outputStore.append(chunk)
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
