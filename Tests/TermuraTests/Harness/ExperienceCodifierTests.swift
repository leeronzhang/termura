import Foundation
import XCTest
@testable import Termura

final class ExperienceCodifierTests: XCTestCase {
    private var dbService: MockDatabaseService!
    private var harnessRepo: HarnessEventRepository!
    private var codifier: ExperienceCodifier!
    private var sessionID: SessionID!

    override func setUp() async throws {
        dbService = try MockDatabaseService()
        harnessRepo = HarnessEventRepository(db: dbService)
        codifier = ExperienceCodifier(harnessEventRepo: harnessRepo)
        sessionID = SessionID()

        let session = SessionRecord(id: sessionID, title: "Test")
        let sessionRepo = SessionRepository(db: dbService)
        try await sessionRepo.save(session)
    }

    // MARK: - Helpers

    private func makeChunk(
        command: String = "npm test",
        output: [String] = ["error: something failed"],
        exitCode: Int? = 1
    ) -> OutputChunk {
        OutputChunk(
            sessionID: sessionID,
            commandText: command,
            outputLines: output,
            rawANSI: output.joined(separator: "\n"),
            exitCode: exitCode,
            startedAt: Date(),
            finishedAt: Date(),
            contentType: .error
        )
    }

    private func makeTempFile(content: String) throws -> String {
        let path = NSTemporaryDirectory() + "codifier-test-\(UUID().uuidString).md"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    // MARK: - Draft generation

    func testGenerateDraftContainsErrorTitle() async {
        let chunk = makeChunk(output: ["error: module not found", "at line 42"])
        let draft = await codifier.generateDraft(from: chunk)
        XCTAssertTrue(draft.errorSummary.title.contains("error: module not found"))
    }

    func testGenerateDraftWithEmptyCommandUsesGenericContext() async {
        let chunk = makeChunk(command: "", output: ["fatal: not a git repository"])
        let draft = await codifier.generateDraft(from: chunk)
        XCTAssertTrue(draft.errorSummary.context.contains("running this operation"))
    }

    func testGenerateDraftWithCommandUsesCommandContext() async {
        let chunk = makeChunk(command: "npm test")
        let draft = await codifier.generateDraft(from: chunk)
        XCTAssertTrue(draft.errorSummary.context.contains("running `npm test`"))
    }

    func testGenerateDraftTruncatesLongErrorLine() async {
        let longLine = "error: " + String(repeating: "x", count: 200)
        let chunk = makeChunk(output: [longLine])
        let draft = await codifier.generateDraft(from: chunk)
        XCTAssertLessThanOrEqual(draft.errorSummary.title.count, 80)
    }

    func testGenerateDraftFieldsPopulated() async {
        let chunk = makeChunk()
        let draft = await codifier.generateDraft(from: chunk)
        XCTAssertEqual(draft.errorChunkID, chunk.id)
        XCTAssertEqual(draft.sessionID, chunk.sessionID)
        XCTAssertFalse(draft.suggestedRule.isEmpty)
        XCTAssertFalse(draft.errorSummary.title.isEmpty)
    }

    func testGenerateDraftContainsDateComment() async {
        let chunk = makeChunk()
        let draft = await codifier.generateDraft(from: chunk)
        XCTAssertTrue(draft.suggestedRule.contains("Codified from session error on"))
    }

    // MARK: - Error extraction

    func testExtractErrorSummaryFindsFatalKeyword() async {
        let chunk = makeChunk(output: ["fatal: not a git repository"])
        let draft = await codifier.generateDraft(from: chunk)
        XCTAssertTrue(draft.errorSummary.title.contains("fatal:"))
    }

    func testExtractErrorSummaryFallsBackToFirstLine() async {
        let chunk = makeChunk(output: ["something weird happened", "more details"])
        let draft = await codifier.generateDraft(from: chunk)
        XCTAssertTrue(draft.errorSummary.title.contains("something weird happened"))
    }

    // MARK: - Rule append (file I/O)

    func testAppendRuleWritesToFile() async throws {
        let path = try makeTempFile(content: "# Existing Rules\n\nSome content.")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let chunk = makeChunk()
        let draft = await codifier.generateDraft(from: chunk)
        try await codifier.appendRule(draft: draft, to: path, sessionID: sessionID)

        let result = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(result.contains("# Existing Rules"))
        XCTAssertTrue(result.contains("## Avoid:"))
    }

    func testAppendRuleBackupIsCleanedUp() async throws {
        let path = try makeTempFile(content: "original")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let chunk = makeChunk()
        let draft = await codifier.generateDraft(from: chunk)
        try await codifier.appendRule(draft: draft, to: path, sessionID: sessionID)

        let backupPath = path + ".backup"
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupPath))
    }

    func testAppendRuleSavesHarnessEvent() async throws {
        let path = try makeTempFile(content: "content")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let chunk = makeChunk()
        let draft = await codifier.generateDraft(from: chunk)
        try await codifier.appendRule(draft: draft, to: path, sessionID: sessionID)

        let events = try await harnessRepo.fetchEvents(for: sessionID)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.first?.eventType, .ruleAppend)
    }

    func testAppendRuleToNonexistentFileThrows() async {
        let fakePath = "/tmp/nonexistent-\(UUID().uuidString).md"
        let chunk = makeChunk()
        let draft = await codifier.generateDraft(from: chunk)

        do {
            try await codifier.appendRule(draft: draft, to: fakePath, sessionID: sessionID)
            XCTFail("Expected file read error")
        } catch {
            // Expected: file not found.
        }
    }
}
