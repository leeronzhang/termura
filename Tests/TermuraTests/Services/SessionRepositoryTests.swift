import XCTest
@testable import Termura

final class SessionRepositoryTests: XCTestCase {
    private var dbService: MockDatabaseService!
    private var repository: SessionRepository!

    override func setUp() async throws {
        dbService = try MockDatabaseService()
        repository = SessionRepository(db: dbService)
    }

    func testSaveAndFetchAll() async throws {
        let record = SessionRecord(title: "Test Session")
        try await repository.save(record)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Test Session")
    }

    func testDeleteRemovesRecord() async throws {
        let record = SessionRecord(title: "To Delete")
        try await repository.save(record)
        try await repository.delete(id: record.id)

        let all = try await repository.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testArchiveHidesFromFetchAll() async throws {
        let record = SessionRecord(title: "Archive Me")
        try await repository.save(record)
        try await repository.archive(id: record.id)

        let all = try await repository.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testSearchFindsMatchingTitle() async throws {
        let record = SessionRecord(title: "UniqueSearchTitle")
        try await repository.save(record)

        let results = try await repository.search(query: "UniqueSearch")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.title, "UniqueSearchTitle")
    }

    func testSearchReturnsEmptyForShortQuery() async throws {
        let record = SessionRecord(title: "Something")
        try await repository.save(record)

        let results = try await repository.search(query: "S")
        XCTAssertTrue(results.isEmpty)
    }

    func testReorderUpdatesOrderIndex() async throws {
        let first = SessionRecord(title: "First", orderIndex: 0)
        let second = SessionRecord(title: "Second", orderIndex: 1)
        try await repository.save(first)
        try await repository.save(second)

        try await repository.reorder(ids: [second.id, first.id])

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.title, "Second")
    }

    func testSetColorLabel() async throws {
        let record = SessionRecord(title: "ColorTest", colorLabel: .none)
        try await repository.save(record)

        try await repository.setColorLabel(id: record.id, label: .blue)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.colorLabel, .blue)
    }

    func testSetPinned() async throws {
        let record = SessionRecord(title: "PinTest", isPinned: false)
        try await repository.save(record)

        try await repository.setPinned(id: record.id, pinned: true)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.isPinned, true)
    }
}
