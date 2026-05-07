import Foundation
@testable import Termura
import XCTest

final class SessionSnapshotRepositoryTests: XCTestCase {
    private var dbService: MockDatabaseService!
    private var repository: SessionSnapshotRepository!
    private var sessionID: SessionID!

    override func setUp() async throws {
        dbService = try MockDatabaseService()
        repository = SessionSnapshotRepository(db: dbService)
        sessionID = SessionID()

        let session = SessionRecord(id: sessionID, title: "Test")
        let sessionRepo = SessionRepository(db: dbService)
        try await sessionRepo.save(session)
    }

    // MARK: - Round-trip

    func testSaveAndLoadRoundTrip() async throws {
        let lines = (0 ..< 10).map { "Line \($0)" }
        try await repository.save(lines: lines, for: sessionID)

        let loaded = try await repository.load(for: sessionID)
        XCTAssertEqual(loaded, lines)
    }

    func testSaveAndLoadPreservesUnicode() async throws {
        // Unicode test data: CJK, emoji, Arabic, accented Latin
        let lines = ["\u{4F60}\u{597D}\u{4E16}\u{754C}", "\u{1F680}\u{1F525}\u{1F4AF}", "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}", "caf\u{00E9} r\u{00E9}sum\u{00E9}"]
        try await repository.save(lines: lines, for: sessionID)

        let loaded = try await repository.load(for: sessionID)
        XCTAssertEqual(loaded, lines)
    }

    func testSaveAndLoadPreservesEmptyLines() async throws {
        let lines = ["first", "", "third", "", ""]
        try await repository.save(lines: lines, for: sessionID)

        let loaded = try await repository.load(for: sessionID)
        XCTAssertEqual(loaded, lines)
    }

    func testSaveAndLoadSingleLine() async throws {
        let lines = ["only one"]
        try await repository.save(lines: lines, for: sessionID)

        let loaded = try await repository.load(for: sessionID)
        XCTAssertEqual(loaded, lines)
    }

    // MARK: - Line capping

    func testSaveCapsLinesAtSnapshotMaxLines() async throws {
        let maxLines = AppConfig.Persistence.snapshotMaxLines
        let oversized = (0 ..< maxLines + 100).map { "Line \($0)" }
        try await repository.save(lines: oversized, for: sessionID)

        let result = try await repository.load(for: sessionID)
        let loaded = try XCTUnwrap(result)
        XCTAssertEqual(loaded.count, maxLines)
        // Should keep the suffix (last N lines).
        XCTAssertEqual(loaded.first, "Line 100")
        XCTAssertEqual(loaded.last, "Line \(maxLines + 99)")
    }

    // MARK: - NULL handling

    func testLoadForNonexistentSessionReturnsNil() async throws {
        let randomID = SessionID()
        let result = try await repository.load(for: randomID)
        XCTAssertNil(result)
    }

    // MARK: - Delete

    func testDeleteRemovesSnapshot() async throws {
        try await repository.save(lines: ["data"], for: sessionID)
        try await repository.delete(for: sessionID)

        let loaded = try await repository.load(for: sessionID)
        XCTAssertNil(loaded)
    }

    // MARK: - Overwrite

    func testSaveOverwritesPreviousSnapshot() async throws {
        try await repository.save(lines: ["version 1"], for: sessionID)
        try await repository.save(lines: ["version 2"], for: sessionID)

        let loaded = try await repository.load(for: sessionID)
        XCTAssertEqual(loaded, ["version 2"])
    }
}
