import XCTest
@testable import Termura

final class NoteRepositoryTests: XCTestCase {
    private var dbService: MockDatabaseService!
    private var repository: NoteRepository!

    override func setUp() async throws {
        dbService = try MockDatabaseService()
        repository = NoteRepository(db: dbService)
    }

    func testSaveAndFetchAll() async throws {
        let note = NoteRecord(title: "Test Note", body: "Hello world")
        try await repository.save(note)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Test Note")
    }

    func testDeleteRemovesNote() async throws {
        let note = NoteRecord(title: "Delete Me")
        try await repository.save(note)
        try await repository.delete(id: note.id)

        let all = try await repository.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testSearchFindsMatchingTitle() async throws {
        let note = NoteRecord(title: "UniqueNoteTitle", body: "Some content")
        try await repository.save(note)

        let results = try await repository.search(query: "UniqueNote")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.title, "UniqueNoteTitle")
    }

    func testSearchFindsMatchingBody() async throws {
        let note = NoteRecord(title: "Untitled", body: "DistinctBodyContent")
        try await repository.save(note)

        let results = try await repository.search(query: "DistinctBody")
        XCTAssertFalse(results.isEmpty)
    }

    func testSearchReturnsEmptyForShortQuery() async throws {
        let note = NoteRecord(title: "Something")
        try await repository.save(note)

        let results = try await repository.search(query: "S")
        XCTAssertTrue(results.isEmpty)
    }

    func testSaveUpdatesUpdatedAt() async throws {
        var note = NoteRecord(title: "Original")
        try await repository.save(note)

        let originalUpdatedAt = note.updatedAt
        note.title = "Updated"
        // Small delay to ensure timestamp changes
        try await yieldForDuration(seconds: 0.01)
        try await repository.save(note)

        let all = try await repository.fetchAll()
        let saved = try XCTUnwrap(all.first)
        XCTAssertGreaterThanOrEqual(saved.updatedAt, originalUpdatedAt)
    }

    func testFetchAllOrderedByUpdatedAtDesc() async throws {
        let first = NoteRecord(title: "First")
        let second = NoteRecord(title: "Second")
        try await repository.save(first)
        try await yieldForDuration(seconds: 0.02)
        try await repository.save(second)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.title, "Second")
    }
}
