import XCTest
@testable import Termura

final class SearchServiceTests: XCTestCase {
    private var sessionRepo: MockSessionRepository!
    private var noteRepo: MockNoteRepository!
    private var searchService: SearchService!

    override func setUp() async throws {
        sessionRepo = MockSessionRepository()
        noteRepo = MockNoteRepository()
        searchService = SearchService(
            sessionRepository: sessionRepo,
            noteRepository: noteRepo
        )
    }

    func testEmptyQueryReturnsEmpty() async throws {
        let results = try await searchService.search(query: "")
        XCTAssertTrue(results.sessions.isEmpty)
        XCTAssertTrue(results.notes.isEmpty)
        XCTAssertEqual(results.query, "")
    }

    func testShortQueryReturnsEmpty() async throws {
        let session = SessionRecord(title: "My Session")
        try await sessionRepo.save(session)

        let results = try await searchService.search(query: "M")
        XCTAssertTrue(results.sessions.isEmpty)
        XCTAssertTrue(results.notes.isEmpty)
    }

    func testSearchFindsSessionsAndNotesConcurrently() async throws {
        let session = SessionRecord(title: "TargetSession")
        let note = NoteRecord(title: "TargetNote", body: "content")
        try await sessionRepo.save(session)
        try await noteRepo.save(note)

        let results = try await searchService.search(query: "Target")
        XCTAssertFalse(results.sessions.isEmpty)
        XCTAssertFalse(results.notes.isEmpty)
        XCTAssertEqual(results.query, "Target")
    }

    func testSearchReturnsOnlyMatchingSessions() async throws {
        let matching = SessionRecord(title: "FindMe")
        let nonMatching = SessionRecord(title: "Other")
        try await sessionRepo.save(matching)
        try await sessionRepo.save(nonMatching)

        let results = try await searchService.search(query: "FindMe")
        XCTAssertEqual(results.sessions.count, 1)
        XCTAssertEqual(results.sessions.first?.title, "FindMe")
    }

    func testSearchReturnsOnlyMatchingNotes() async throws {
        let matching = NoteRecord(title: "FindNote", body: "")
        let nonMatching = NoteRecord(title: "Irrelevant", body: "")
        try await noteRepo.save(matching)
        try await noteRepo.save(nonMatching)

        let results = try await searchService.search(query: "FindNote")
        XCTAssertEqual(results.notes.count, 1)
        XCTAssertEqual(results.notes.first?.title, "FindNote")
    }
}
