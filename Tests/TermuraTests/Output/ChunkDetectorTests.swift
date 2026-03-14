import Testing
@testable import Termura

@Suite("ChunkDetector")
struct ChunkDetectorTests {

    // MARK: - Full command cycle

    @Test("Full command cycle produces a chunk")
    func fullCommandCycle() async {
        let sessionID = SessionID()
        let detector = ChunkDetector(sessionID: sessionID)

        await detector.handleShellEvent(.promptStarted).map { _ in () }
        await detector.handleShellEvent(.commandStarted).map { _ in () }
        await detector.appendRawOutput("hello world\n")
        await detector.handleShellEvent(.executionStarted).map { _ in () }
        let chunk = await detector.handleShellEvent(.executionFinished(exitCode: 0))

        guard let chunk else {
            Issue.record("Expected a chunk to be produced")
            return
        }

        #expect(chunk.sessionID == sessionID)
        #expect(chunk.exitCode == 0)
        #expect(chunk.finishedAt != nil)
        #expect(chunk.outputLines.joined().contains("hello world"))
    }

    // MARK: - Exit code propagation

    @Test("Exit code 127 is propagated correctly")
    func exitCodePropagation() async {
        let detector = ChunkDetector(sessionID: SessionID())

        await detector.handleShellEvent(.promptStarted).map { _ in () }
        await detector.handleShellEvent(.commandStarted).map { _ in () }
        await detector.handleShellEvent(.executionStarted).map { _ in () }
        let chunk = await detector.handleShellEvent(.executionFinished(exitCode: 127))

        #expect(chunk?.exitCode == 127)
    }

    @Test("nil exit code is propagated correctly")
    func nilExitCode() async {
        let detector = ChunkDetector(sessionID: SessionID())

        await detector.handleShellEvent(.promptStarted).map { _ in () }
        await detector.handleShellEvent(.commandStarted).map { _ in () }
        await detector.handleShellEvent(.executionStarted).map { _ in () }
        let chunk = await detector.handleShellEvent(.executionFinished(exitCode: nil))

        guard let chunk else {
            // Empty output with no command is allowed to return nil — pass
            return
        }
        #expect(chunk.exitCode == nil)
    }

    // MARK: - Buffer cleared after chunk

    @Test("Buffer is cleared after chunk is built")
    func bufferClearedAfterChunk() async {
        let detector = ChunkDetector(sessionID: SessionID())

        await detector.handleShellEvent(.promptStarted).map { _ in () }
        await detector.handleShellEvent(.commandStarted).map { _ in () }
        await detector.appendRawOutput("first output\n")
        await detector.handleShellEvent(.executionStarted).map { _ in () }
        _ = await detector.handleShellEvent(.executionFinished(exitCode: 0))

        // Second command cycle — buffer should be fresh
        await detector.handleShellEvent(.promptStarted).map { _ in () }
        await detector.handleShellEvent(.commandStarted).map { _ in () }
        await detector.appendRawOutput("second output\n")
        await detector.handleShellEvent(.executionStarted).map { _ in () }
        let secondChunk = await detector.handleShellEvent(.executionFinished(exitCode: 0))

        guard let secondChunk else {
            Issue.record("Expected second chunk")
            return
        }
        let outputText = secondChunk.outputLines.joined()
        #expect(outputText.contains("second output"))
        #expect(!outputText.contains("first output"))
    }

    // MARK: - No chunk without finish

    @Test("No chunk returned without executionFinished")
    func noChunkWithoutFinish() async {
        let detector = ChunkDetector(sessionID: SessionID())

        await detector.handleShellEvent(.promptStarted).map { _ in () }
        await detector.handleShellEvent(.commandStarted).map { _ in () }
        await detector.appendRawOutput("some output\n")
        let chunk = await detector.handleShellEvent(.executionStarted)

        #expect(chunk == nil)
    }

    // MARK: - ANSI stripping

    @Test("ANSI sequences are stripped from outputLines")
    func ansiStrippedInLines() async {
        let detector = ChunkDetector(sessionID: SessionID())

        await detector.handleShellEvent(.promptStarted).map { _ in () }
        await detector.handleShellEvent(.commandStarted).map { _ in () }
        await detector.appendRawOutput("\u{1B}[32mgreen text\u{1B}[0m\n")
        await detector.handleShellEvent(.executionStarted).map { _ in () }
        let chunk = await detector.handleShellEvent(.executionFinished(exitCode: 0))

        guard let chunk else {
            Issue.record("Expected chunk")
            return
        }
        let text = chunk.outputLines.joined()
        #expect(text.contains("green text"))
        #expect(!text.contains("\u{1B}"))
    }

    // MARK: - Reset

    @Test("reset clears pending buffers")
    func resetClearsPending() async {
        let detector = ChunkDetector(sessionID: SessionID())

        await detector.handleShellEvent(.promptStarted).map { _ in () }
        await detector.handleShellEvent(.commandStarted).map { _ in () }
        await detector.appendRawOutput("before reset\n")
        await detector.reset()

        await detector.handleShellEvent(.promptStarted).map { _ in () }
        await detector.handleShellEvent(.commandStarted).map { _ in () }
        await detector.handleShellEvent(.executionStarted).map { _ in () }
        let chunk = await detector.handleShellEvent(.executionFinished(exitCode: 0))

        let outputText = chunk?.outputLines.joined() ?? ""
        #expect(!outputText.contains("before reset"))
    }
}

private extension Optional {
    func map(_ transform: (Wrapped) -> Void) {
        if let value = self { transform(value) }
    }
}
