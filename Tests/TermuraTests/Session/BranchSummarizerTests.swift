import Foundation
import Testing
@testable import Termura

@Suite("BranchSummarizer")
struct BranchSummarizerTests {
    private let summarizer = BranchSummarizer()

    private func makeChunk(
        command: String = "echo test",
        output: [String] = ["test"],
        exitCode: Int? = 0,
        contentType: OutputContentType = .commandOutput
    ) -> OutputChunk {
        OutputChunk(
            sessionID: SessionID(),
            commandText: command,
            outputLines: output,
            rawANSI: output.joined(separator: "\n"),
            exitCode: exitCode,
            startedAt: Date(),
            finishedAt: Date(),
            contentType: contentType
        )
    }

    // MARK: - Summary generation

    @Test("Empty chunks returns empty message")
    func emptyChunks() async {
        let summary = await summarizer.summarize(chunks: [], branchType: .main)
        #expect(summary == "Empty branch session.")
    }

    @Test("Single command uses singular grammar")
    func singularGrammar() async {
        let chunks = [makeChunk()]
        let summary = await summarizer.summarize(chunks: chunks, branchType: .main)
        #expect(summary.contains("1 command"))
        #expect(!summary.contains("1 commands"))
    }

    @Test("Multiple commands use plural grammar")
    func pluralGrammar() async {
        let chunks = [makeChunk(), makeChunk(), makeChunk()]
        let summary = await summarizer.summarize(chunks: chunks, branchType: .main)
        #expect(summary.contains("3 commands"))
    }

    @Test("Error count included when non-zero exit codes")
    func errorCountIncluded() async {
        let chunks = [
            makeChunk(exitCode: 0),
            makeChunk(exitCode: 1),
            makeChunk(exitCode: 2)
        ]
        let summary = await summarizer.summarize(chunks: chunks, branchType: .main)
        #expect(summary.contains("2 errors"))
    }

    @Test("No error count when all succeed")
    func noErrorCountWhenAllSucceed() async {
        let chunks = [makeChunk(exitCode: 0), makeChunk(exitCode: 0)]
        let summary = await summarizer.summarize(chunks: chunks, branchType: .main)
        #expect(!summary.contains("error"))
    }

    @Test("Top commands limited to five")
    func topCommandsLimit() async {
        let chunks = (0 ..< 7).map { i in makeChunk(command: "cmd\(i)") }
        let summary = await summarizer.summarize(chunks: chunks, branchType: .main)
        let backtickCount = summary.components(separatedBy: "`").count - 1
        // 5 commands × 2 backticks each = 10 backticks max
        #expect(backtickCount <= 10)
    }

    @Test("Empty commands are excluded from key commands")
    func emptyCommandsExcluded() async {
        let chunks = [makeChunk(command: ""), makeChunk(command: "git status")]
        let summary = await summarizer.summarize(chunks: chunks, branchType: .main)
        #expect(summary.contains("`git status`"))
        #expect(!summary.contains("``"))
    }

    @Test("Error lines included for error content type")
    func errorLinesIncluded() async {
        let chunks = [
            makeChunk(
                output: ["error: module not found", "at line 42"],
                exitCode: 1,
                contentType: .error
            )
        ]
        let summary = await summarizer.summarize(chunks: chunks, branchType: .fix)
        #expect(summary.contains("Errors:"))
    }

    @Test("Summary truncated at max length")
    func summaryTruncated() async {
        let longOutput = (0 ..< 100).map { "error line \($0): " + String(repeating: "x", count: 50) }
        let chunks = [
            makeChunk(output: longOutput, exitCode: 1, contentType: .error)
        ]
        let summary = await summarizer.summarize(chunks: chunks, branchType: .main)
        #expect(summary.count <= AppConfig.SessionTree.summaryMaxLength)
    }

    // MARK: - Summary message

    @Test("Created summary message has correct fields")
    func summaryMessageFields() async {
        let branchID = SessionID()
        let parentID = SessionID()
        let msg = await summarizer.createSummaryMessage(
            summary: "test summary",
            branchSessionID: branchID,
            parentSessionID: parentID
        )
        #expect(msg.role == .system)
        #expect(msg.contentType == .metadata)
        #expect(msg.sessionID == parentID)
        #expect(msg.content.contains(branchID.rawValue.uuidString))
    }
}
