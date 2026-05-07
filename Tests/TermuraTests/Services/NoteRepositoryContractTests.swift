import Foundation
@testable import Termura
import XCTest

/// Contract tests verifying that MockNoteRepository preserves the same behavioral
/// guarantees as NoteRepository for the operations it is designed to mirror.
///
/// Search accuracy is excluded: MockNoteRepository uses substring matching while
/// NoteRepository uses FTS5. Search-specific coverage lives in NoteRepositoryTests.swift.
final class NoteRepositoryContractTests: XCTestCase {
    // MARK: - Round-trip

    /// Both implementations must return the saved note on fetchAll.
    func testSaveAndFetchAllContract() async throws {
        let note = NoteRecord(title: "Contract Note", body: "body content")

        let mock = MockNoteRepository()
        try await mock.save(note)
        let mockResult = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = NoteRepository(db: db)
        try await real.save(note)
        let realResult = try await real.fetchAll()

        XCTAssertEqual(mockResult.count, 1)
        XCTAssertEqual(realResult.count, 1)
        XCTAssertEqual(mockResult.first?.id, note.id)
        XCTAssertEqual(realResult.first?.id, note.id)
        XCTAssertEqual(mockResult.first?.title, realResult.first?.title)
        XCTAssertEqual(mockResult.first?.body, realResult.first?.body)
    }

    // MARK: - Delete

    /// Both implementations must return empty after save-then-delete.
    func testDeleteContract() async throws {
        let note = NoteRecord(title: "Delete Contract")

        let mock = MockNoteRepository()
        try await mock.save(note)
        try await mock.delete(id: note.id)
        let mockResult = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = NoteRepository(db: db)
        try await real.save(note)
        try await real.delete(id: note.id)
        let realResult = try await real.fetchAll()

        XCTAssertTrue(mockResult.isEmpty)
        XCTAssertTrue(realResult.isEmpty)
    }

    // MARK: - Empty state

    /// Both implementations must return empty when nothing has been saved.
    func testFetchAllEmptyContract() async throws {
        let mock = MockNoteRepository()
        let mockResult = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = NoteRepository(db: db)
        let realResult = try await real.fetchAll()

        XCTAssertTrue(mockResult.isEmpty)
        XCTAssertTrue(realResult.isEmpty)
    }

    // MARK: - isFavorite round-trip

    /// Both implementations must preserve the isFavorite flag on save/fetch.
    func testFavoriteFieldRoundTripContract() async throws {
        let favoriteNote = NoteRecord(title: "Favorite Note", body: "snippet body", isFavorite: true)
        let regularNote = NoteRecord(title: "Regular Note", body: "regular body", isFavorite: false)

        let mock = MockNoteRepository()
        try await mock.save(favoriteNote)
        try await mock.save(regularNote)
        let mockAll = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = NoteRepository(db: db)
        try await real.save(favoriteNote)
        try await real.save(regularNote)
        let realAll = try await real.fetchAll()

        let mockFavorite = mockAll.first { $0.id == favoriteNote.id }
        let realFavorite = realAll.first { $0.id == favoriteNote.id }
        XCTAssertEqual(mockFavorite?.isFavorite, true)
        XCTAssertEqual(realFavorite?.isFavorite, true)

        let mockRegular = mockAll.first { $0.id == regularNote.id }
        let realRegular = realAll.first { $0.id == regularNote.id }
        XCTAssertEqual(mockRegular?.isFavorite, false)
        XCTAssertEqual(realRegular?.isFavorite, false)
    }

    // MARK: - Multiple notes round-trip

    /// Both implementations must return all saved notes (set equality on IDs).
    func testMultipleSavesReturnAllContract() async throws {
        let noteA = NoteRecord(title: "Alpha")
        let noteB = NoteRecord(title: "Beta")
        let noteC = NoteRecord(title: "Gamma")

        let mock = MockNoteRepository()
        try await mock.save(noteA)
        try await mock.save(noteB)
        try await mock.save(noteC)
        let mockResult = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = NoteRepository(db: db)
        try await real.save(noteA)
        try await real.save(noteB)
        try await real.save(noteC)
        let realResult = try await real.fetchAll()

        XCTAssertEqual(mockResult.count, 3)
        XCTAssertEqual(realResult.count, 3)

        let mockIDs = Set(mockResult.map(\.id))
        let realIDs = Set(realResult.map(\.id))
        XCTAssertEqual(mockIDs, Set([noteA.id, noteB.id, noteC.id]))
        XCTAssertEqual(realIDs, Set([noteA.id, noteB.id, noteC.id]))
        XCTAssertEqual(mockIDs, realIDs)
    }

    // MARK: - Delete unknown ID is a no-op

    /// Both implementations must leave existing notes intact when deleting a nonexistent ID.
    func testDeleteUnknownIDIsNoopContract() async throws {
        let note = NoteRecord(title: "Survivor")
        let unknownID = NoteID()

        let mock = MockNoteRepository()
        try await mock.save(note)
        try await mock.delete(id: unknownID)
        let mockResult = try await mock.fetchAll()

        let db = try MockDatabaseService()
        let real = NoteRepository(db: db)
        try await real.save(note)
        try await real.delete(id: unknownID)
        let realResult = try await real.fetchAll()

        XCTAssertEqual(mockResult.count, 1)
        XCTAssertEqual(realResult.count, 1)
        XCTAssertEqual(mockResult.first?.id, note.id)
        XCTAssertEqual(realResult.first?.id, note.id)
    }
}
