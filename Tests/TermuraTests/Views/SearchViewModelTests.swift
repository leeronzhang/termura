import Foundation
import XCTest
@testable import Termura

@MainActor
final class SearchViewModelTests: XCTestCase {
    private var sessionRepo: MockSessionRepository!
    private var noteRepo: MockNoteRepository!
    private var searchService: SearchService!
    private var viewModel: SearchViewModel!

    override func setUp() async throws {
        sessionRepo = MockSessionRepository()
        noteRepo = MockNoteRepository()
        searchService = SearchService(
            sessionRepository: sessionRepo,
            noteRepository: noteRepo
        )
        viewModel = SearchViewModel(searchService: searchService)
    }

    // MARK: - Query handling

    func testShortQueryClearsResults() async throws {
        // Pre-populate so we know results get cleared.
        let session = SessionRecord(title: "FindableSession")
        try await sessionRepo.save(session)

        viewModel.query = "Fi"
        // Wait for debounce.
        try await Task.sleep(for: .milliseconds(500))
        viewModel.query = "F"
        try await Task.sleep(for: .milliseconds(500))

        // Query "F" is < minQueryLength, results should be empty.
        XCTAssertTrue(viewModel.results.sessions.isEmpty && viewModel.results.notes.isEmpty)
    }

    func testSearchingStateTransitions() async throws {
        let session = SessionRecord(title: "SearchTarget")
        try await sessionRepo.save(session)

        XCTAssertFalse(viewModel.isSearching)

        viewModel.query = "SearchTarget"
        // Debounce fires after searchDebounceSeconds.
        try await Task.sleep(for: .milliseconds(600))

        // After search completes, isSearching should be false.
        XCTAssertFalse(viewModel.isSearching)
    }

    func testSearchFindsMatchingSession() async throws {
        let session = SessionRecord(title: "UniqueMatchTitle")
        try await sessionRepo.save(session)

        viewModel.query = "UniqueMatch"
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertFalse(viewModel.results.sessions.isEmpty)
    }

    func testEmptyQueryProducesEmptyResults() {
        viewModel.query = ""
        XCTAssertTrue(viewModel.results.sessions.isEmpty && viewModel.results.notes.isEmpty)
    }
}
