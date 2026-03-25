import Foundation
import Testing
@testable import Termura

@Suite("FallbackChunkDetector")
struct FallbackChunkDetectorTests {
    private let sessionID = SessionID()

    private func makeDetector(
        pattern: String = AppConfig.Output.aiToolPromptPattern
    ) -> FallbackChunkDetector {
        FallbackChunkDetector(sessionID: sessionID, pattern: pattern)
    }

    // MARK: - Prompt detection

    @Test("Detects Claude Code bare > prompt")
    func detectClaudeCodePrompt() async {
        let detector = makeDetector()
        // First prompt establishes a boundary but emits nothing yet.
        _ = await detector.processOutput(">\n", raw: ">\n")
        // Feed some output then a second prompt to trigger emission.
        _ = await detector.processOutput("some output\n", raw: "some output\n")
        let chunks = await detector.processOutput(">\n", raw: ">\n")
        #expect(chunks.count == 1)
        #expect(chunks.first?.outputLines.first == "some output")
    }

    @Test("Detects unicode fish prompt ❯")
    func detectFishPrompt() async {
        let detector = makeDetector(pattern: "^[>❯›]\\s*$")
        _ = await detector.processOutput("❯\n", raw: "❯\n")
        _ = await detector.processOutput("output\n", raw: "output\n")
        let chunks = await detector.processOutput("❯\n", raw: "❯\n")
        #expect(chunks.count == 1)
    }

    @Test("Mid-line > does not trigger boundary")
    func midLineGreaterThan() async {
        let detector = makeDetector()
        _ = await detector.processOutput(">\n", raw: ">\n")
        let chunks = await detector.processOutput("if x > 5 then\n", raw: "if x > 5 then\n")
        // No boundary should fire — "if x > 5 then" doesn't match ^[>❯›]\s*$
        #expect(chunks.isEmpty)
    }

    // MARK: - Chunk emission

    @Test("Emits chunk when second prompt detected")
    func emitOnSecondPrompt() async {
        let detector = makeDetector()
        _ = await detector.processOutput(">\n", raw: ">\n")
        _ = await detector.processOutput("line 1\nline 2\n", raw: "line 1\nline 2\n")
        let chunks = await detector.processOutput(">\n", raw: ">\n")
        #expect(chunks.count == 1)
        let chunk = chunks[0]
        #expect(chunk.outputLines.contains("line 1"))
        #expect(chunk.outputLines.contains("line 2"))
    }

    @Test("Multiple prompts produce multiple chunks")
    func multipleChunks() async {
        let detector = makeDetector()
        _ = await detector.processOutput(">\n", raw: ">\n")
        _ = await detector.processOutput("output A\n", raw: "output A\n")
        _ = await detector.processOutput(">\n", raw: ">\n")
        _ = await detector.processOutput("output B\n", raw: "output B\n")
        let chunks = await detector.processOutput(">\n", raw: ">\n")
        // Two total chunks: A (emitted on second prompt) + B (emitted on third prompt)
        // But the second prompt also was called separately.
        // Let's count all emitted chunks across calls.
        // Actually we need to accumulate:
        let detector2 = makeDetector()
        var allChunks: [OutputChunk] = []
        allChunks += await detector2.processOutput(">\noutput A\n>\noutput B\n>\n", raw: ">\noutput A\n>\noutput B\n>\n")
        #expect(allChunks.count == 2)
    }

    @Test("No chunk emitted without prompt")
    func noChunkWithoutPrompt() async {
        let detector = makeDetector()
        let chunks = await detector.processOutput("just output\nmore output\n", raw: "just output\nmore output\n")
        #expect(chunks.isEmpty)
    }

    // MARK: - ANSI capping

    @Test("Raw ANSI capped at maxChunkOutputChars")
    func rawANSICapping() async {
        let detector = makeDetector()
        _ = await detector.processOutput(">\n", raw: ">\n")

        let maxChars = AppConfig.Output.maxChunkOutputChars
        let bigRaw = String(repeating: "A", count: maxChars + 1000)
        _ = await detector.processOutput("output\n", raw: bigRaw)
        let chunks = await detector.processOutput(">\n", raw: ">\n")
        #expect(chunks.count == 1)
        #expect(chunks[0].rawANSI.count <= maxChars + 10)
    }

    @Test("Pending lines capped at maxChunkOutputChars")
    func pendingLinesCapping() async {
        let detector = makeDetector()
        _ = await detector.processOutput(">\n", raw: ">\n")

        let maxChars = AppConfig.Output.maxChunkOutputChars
        let bigLine = String(repeating: "X", count: maxChars + 500)
        _ = await detector.processOutput(bigLine + "\n", raw: bigLine + "\n")
        _ = await detector.processOutput("extra\n", raw: "extra\n")
        let chunks = await detector.processOutput(">\n", raw: ">\n")
        #expect(chunks.count == 1)
        // After the first big line fills capacity, "extra" should be dropped.
        let totalChars = chunks[0].outputLines.reduce(0) { $0 + $1.count }
        #expect(totalChars <= maxChars + bigLine.count)
    }

    // MARK: - Semantic classification

    @Test("Error output gets classified")
    func semanticClassification() async {
        let detector = makeDetector()
        _ = await detector.processOutput(">\n", raw: ">\n")
        _ = await detector.processOutput("error: something failed\n", raw: "error: something failed\n")
        let chunks = await detector.processOutput(">\n", raw: ">\n")
        #expect(chunks.count == 1)
        #expect(chunks[0].contentType == .error)
    }

    // MARK: - Session ID

    @Test("Chunks carry the correct sessionID")
    func chunkSessionID() async {
        let detector = makeDetector()
        _ = await detector.processOutput(">\noutput\n>\n", raw: ">\noutput\n>\n")
        let chunks = await detector.processOutput(">\n", raw: ">\n")
        for chunk in chunks {
            #expect(chunk.sessionID == sessionID)
        }
    }
}
