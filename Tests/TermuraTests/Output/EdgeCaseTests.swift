import Testing
@testable import Termura

@Suite("Edge Cases")
struct EdgeCaseTests {

    // MARK: - ANSIStripper Edge Cases

    @Suite("ANSIStripper")
    struct ANSIStripperEdgeCases {

        @Test("Empty string returns empty")
        func emptyInput() {
            #expect(ANSIStripper.strip("") == "")
        }

        @Test("String with ONLY escape sequences returns empty")
        func onlyEscapes() {
            let input = "\u{1B}[31m\u{1B}[0m\u{1B}[1;32m"
            #expect(ANSIStripper.strip(input) == "")
        }

        @Test("Truncated CSI at end of string — partial sequence stripped")
        func truncatedCSI() {
            let input = "hello\u{1B}[31"
            let result = ANSIStripper.strip(input)
            // Partial CSI should be stripped (no final byte)
            #expect(result == "hello")
        }

        @Test("Malformed OSC without terminator strips to end")
        func malformedOSC() {
            let input = "before\u{1B}]0;titleafter"
            let result = ANSIStripper.strip(input)
            // OSC without BEL/ST should strip everything after ESC]
            #expect(!result.contains("title"))
            #expect(result.contains("before"))
        }

        @Test("Interleaved escapes with valid text preserves text")
        func interleavedEscapes() {
            let input = "\u{1B}[1mhello\u{1B}[0m \u{1B}[32mworld\u{1B}[0m"
            #expect(ANSIStripper.strip(input) == "hello world")
        }

        @Test("Very long SGR with many parameters is stripped")
        func longSGR() {
            // SGR with 10 parameters
            let params = (1...10).map(String.init).joined(separator: ";")
            let input = "\u{1B}[\(params)mcolored text\u{1B}[0m"
            #expect(ANSIStripper.strip(input) == "colored text")
        }

        @Test("Unicode text preserved through escape stripping")
        func unicodePreservation() {
            let input = "\u{1B}[33m\u{4F60}\u{597D}\u{4E16}\u{754C}\u{1B}[0m"
            #expect(ANSIStripper.strip(input) == "\u{4F60}\u{597D}\u{4E16}\u{754C}")
        }

        @Test("Charset designation G0 stripped")
        func charsetDesignation() {
            let input = "before\u{1B}(Bafter"
            let result = ANSIStripper.strip(input)
            #expect(result == "beforeafter")
        }
    }

    // MARK: - FallbackChunkDetector Edge Cases

    @Suite("FallbackChunkDetector")
    struct FallbackChunkDetectorEdgeCases {

        @Test("Empty input produces no chunks")
        func emptyInput() async {
            let detector = FallbackChunkDetector(sessionID: SessionID())
            let chunks = await detector.processOutput("", raw: "")
            #expect(chunks.isEmpty)
        }

        @Test("Whitespace-only input produces no chunks")
        func whitespaceOnly() async {
            let detector = FallbackChunkDetector(sessionID: SessionID())
            let chunks = await detector.processOutput("   \n\n  \n", raw: "   \n\n  \n")
            #expect(chunks.isEmpty)
        }

        @Test("Single prompt character produces no chunk content")
        func singlePrompt() async {
            let detector = FallbackChunkDetector(sessionID: SessionID())
            let chunks = await detector.processOutput("$ ", raw: "$ ")
            // Prompt line itself is not content — it's a boundary marker.
            for chunk in chunks {
                let trimmed = chunk.outputLines
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(trimmed.isEmpty || trimmed == "$")
            }
        }
    }

    // MARK: - ChunkDetector Edge Cases

    @Suite("ChunkDetector")
    struct ChunkDetectorEdgeCases {

        @Test("Shell event without output produces chunk with empty output")
        func shellEventNoOutput() async {
            let detector = ChunkDetector(sessionID: SessionID())
            // Start a command cycle with no output
            _ = await detector.handleShellEvent(.promptStarted)
            _ = await detector.handleShellEvent(.commandStarted)
            _ = await detector.handleShellEvent(.executionStarted)
            let chunk = await detector.handleShellEvent(.executionFinished(exitCode: 0))
            // Should still produce a chunk (command ran but produced nothing)
            if let chunk {
                #expect(chunk.outputLines.isEmpty || chunk.outputLines == [""])
            }
        }

        @Test("Back-to-back command cycles produce separate chunks")
        func backToBackCycles() async {
            let detector = ChunkDetector(sessionID: SessionID())
            var chunks: [OutputChunk] = []

            // First cycle
            _ = await detector.handleShellEvent(.promptStarted)
            _ = await detector.handleShellEvent(.commandStarted)
            _ = await detector.handleShellEvent(.executionStarted)
            await detector.appendRawOutput("output1\n")
            if let c = await detector.handleShellEvent(.executionFinished(exitCode: 0)) {
                chunks.append(c)
            }

            // Second cycle immediately
            _ = await detector.handleShellEvent(.promptStarted)
            _ = await detector.handleShellEvent(.commandStarted)
            _ = await detector.handleShellEvent(.executionStarted)
            await detector.appendRawOutput("output2\n")
            if let c = await detector.handleShellEvent(.executionFinished(exitCode: 0)) {
                chunks.append(c)
            }

            #expect(chunks.count == 2)
        }
    }

    // MARK: - SemanticParser Edge Cases

    @Suite("SemanticParser")
    struct SemanticParserEdgeCases {

        @Test("Empty text classifies as commandOutput")
        func emptyText() {
            let result = SemanticParser.classify("")
            #expect(result.type == .commandOutput)
        }

        @Test("Diff-like text without full markers is not classified as diff")
        func partialDiff() {
            let text = "--- This is not a real diff"
            let result = SemanticParser.classify(text)
            #expect(result.type != .diff)
        }

        @Test("Error indicators are individually testable")
        func errorIndicators() {
            for indicator in SemanticParser.errorIndicators {
                let text = "Some prefix \(indicator) some suffix"
                let result = SemanticParser.classify(text)
                #expect(result.type == .error, "Indicator '\(indicator)' should trigger error")
            }
        }

        @Test("Tool call indicators are individually testable")
        func toolCallIndicators() {
            for indicator in SemanticParser.toolCallIndicators {
                let text = "\(indicator) some context"
                let result = SemanticParser.classify(text)
                #expect(result.type == .toolCall, "Indicator '\(indicator)' should trigger toolCall")
            }
        }
    }
}
