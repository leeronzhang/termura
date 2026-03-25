import Foundation
import XCTest
@testable import Termura

final class RuleFileRepositoryTests: XCTestCase {
    private var dbService: MockDatabaseService!
    private var repository: RuleFileRepository!

    override func setUp() async throws {
        dbService = try MockDatabaseService()
        repository = RuleFileRepository(db: dbService)
    }

    // MARK: - Helpers

    private func makeRecord(
        filePath: String = "/project/CLAUDE.md",
        content: String = "# Rules",
        version: Int = 1
    ) -> RuleFileRecord {
        RuleFileRecord(
            filePath: filePath,
            content: content,
            version: version
        )
    }

    // MARK: - Save + fetch

    func testSaveAndFetchLatest() async throws {
        let record = makeRecord()
        try await repository.save(record)

        let latest = try await repository.fetchLatest(for: "/project/CLAUDE.md")
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.filePath, "/project/CLAUDE.md")
        XCTAssertEqual(latest?.content, "# Rules")
        XCTAssertEqual(latest?.version, 1)
    }

    func testFieldsRoundTrip() async throws {
        let record = makeRecord(content: "Full content", version: 3)
        try await repository.save(record)

        let fetched = try await repository.fetchLatest(for: record.filePath)
        let result = try XCTUnwrap(fetched)
        XCTAssertEqual(result.id, record.id)
        XCTAssertEqual(result.content, "Full content")
        XCTAssertEqual(result.version, 3)
        XCTAssertFalse(result.contentHash.isEmpty)
    }

    func testFetchLatestForNonexistentPathReturnsNil() async throws {
        let result = try await repository.fetchLatest(for: "/nonexistent/path.md")
        XCTAssertNil(result)
    }

    // MARK: - Version history

    func testFetchHistoryOrderedByVersionDesc() async throws {
        try await repository.save(makeRecord(version: 1))
        try await repository.save(makeRecord(version: 2))
        try await repository.save(makeRecord(version: 3))

        let history = try await repository.fetchHistory(for: "/project/CLAUDE.md")
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].version, 3)
        XCTAssertEqual(history[1].version, 2)
        XCTAssertEqual(history[2].version, 1)
    }

    func testFetchLatestReturnsHighestVersion() async throws {
        try await repository.save(makeRecord(version: 1))
        try await repository.save(makeRecord(version: 5))
        try await repository.save(makeRecord(version: 3))

        let latest = try await repository.fetchLatest(for: "/project/CLAUDE.md")
        XCTAssertEqual(latest?.version, 5)
    }

    // MARK: - Fetch all (latest per path)

    func testFetchAllReturnsLatestPerPath() async throws {
        try await repository.save(makeRecord(filePath: "/a/CLAUDE.md", version: 1))
        try await repository.save(makeRecord(filePath: "/a/CLAUDE.md", version: 2))
        try await repository.save(makeRecord(filePath: "/b/AGENTS.md", version: 1))

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 2)

        let claudeRecord = all.first { $0.filePath == "/a/CLAUDE.md" }
        XCTAssertEqual(claudeRecord?.version, 2)
    }

    func testFetchAllEmptyReturnsEmpty() async throws {
        let all = try await repository.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }
}
