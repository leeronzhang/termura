import Foundation
@testable import Termura
import XCTest

@MainActor
final class NotesViewModelTests: XCTestCase {
    private var repository: MockNoteRepository!
    private var viewModel: NotesViewModel!

    override func setUp() async throws {
        repository = MockNoteRepository()
        viewModel = NotesViewModel(repository: repository)
    }

    // MARK: - Note CRUD

    func testCreateNoteAddsToList() {
        viewModel.createNote()
        XCTAssertEqual(viewModel.notes.count, 1)
    }

    func testCreateNoteSetsSelectedID() {
        viewModel.createNote()
        XCTAssertNotNil(viewModel.selectedNoteID)
        XCTAssertEqual(viewModel.selectedNoteID, viewModel.notes.first?.id)
    }

    func testCreateNoteSetsEditingFields() {
        viewModel.createNote()
        XCTAssertEqual(viewModel.editingTitle, "Untitled")
        XCTAssertEqual(viewModel.editingBody, "")
    }

    func testDeleteNoteRemovesFromList() async {
        viewModel.createNote()
        let id = viewModel.notes[0].id
        await viewModel.deleteNote(id: id)
        XCTAssertTrue(viewModel.notes.isEmpty)
    }

    func testDeleteSelectedNoteSelectsNext() async {
        viewModel.createNote()
        viewModel.createNote()
        let firstID = viewModel.notes[0].id
        let secondID = viewModel.notes[1].id

        // Select the first, then delete it.
        viewModel.selectNote(id: firstID)
        await viewModel.deleteNote(id: firstID)

        // Should auto-select the remaining note.
        XCTAssertEqual(viewModel.selectedNoteID, secondID)
    }

    func testDeleteOnlyNoteClearsSelection() async {
        viewModel.createNote()
        let id = viewModel.notes[0].id
        await viewModel.deleteNote(id: id)
        XCTAssertNil(viewModel.selectedNoteID)
    }

    // MARK: - Selection

    func testSelectNoteUpdatesEditingFields() async throws {
        // Save a note with known content, then load and select it.
        let note = NoteRecord(title: "Custom Title", body: "Custom Body")
        try await repository.save(note)
        await viewModel.loadNotes()
        viewModel.selectNote(id: note.id)
        XCTAssertEqual(viewModel.editingTitle, "Custom Title")
        XCTAssertEqual(viewModel.editingBody, "Custom Body")
    }

    func testSelectNonexistentNoteIsNoop() {
        viewModel.createNote()
        let originalID = viewModel.selectedNoteID
        viewModel.selectNote(id: NoteID())
        XCTAssertEqual(viewModel.selectedNoteID, originalID)
    }

    // MARK: - Load

    func testLoadNotesPopulatesList() async throws {
        let note = NoteRecord(title: "Saved Note", body: "Saved Body")
        try await repository.save(note)

        await viewModel.loadNotes()
        XCTAssertEqual(viewModel.notes.count, 1)
        XCTAssertEqual(viewModel.notes.first?.title, "Saved Note")
    }

    /// Regression: previously a sidebar tab cycle could re-trigger `.task { loadNotes() }`,
    /// replacing `notes` with the disk-backed copy and clobbering an in-memory edit before
    /// autosave had a chance to persist it. loadNotes must be a no-op once initially loaded.
    func testLoadNotesIsIdempotentAfterFirstLoad() async throws {
        let note = NoteRecord(title: "Original", body: "Original Body")
        try await repository.save(note)
        await viewModel.loadNotes()
        viewModel.selectNote(id: note.id)
        viewModel.editingBody = "Edited Body"

        // Simulate a view re-mount calling loadNotes() again — must NOT replace
        // the in-memory note with the disk-backed (still "Original Body") copy.
        await viewModel.loadNotes()

        XCTAssertEqual(viewModel.notes[0].body, "Edited Body")
        XCTAssertEqual(viewModel.editingBody, "Edited Body")
    }

    /// Regression: rapid persistCurrentNote calls used cancel-and-replace, but Swift Task
    /// cancellation is cooperative — the "cancelled" save still raced the new one on the
    /// repository actor, sometimes leaving disk pinned to the older content. The new
    /// chain semantics must (a) keep every persist's Task tracked and (b) deliver the
    /// last call's content to disk after the chain settles.
    func testSerialChainPersistsAllAndKeepsLatest() async throws {
        let note = NoteRecord(title: "T0", body: "B0")
        try await repository.save(note)
        await viewModel.loadNotes()
        viewModel.selectNote(id: note.id)

        viewModel.persistCurrentNote(title: "T1", body: "B1")
        viewModel.persistCurrentNote(title: "T2", body: "B2")
        viewModel.persistCurrentNote(title: "T3", body: "B3")

        // Chaining (vs. cancel-and-replace) keeps every Task tracked.
        XCTAssertEqual(viewModel.pendingWrites.count, 3)

        // Awaiting the chain head transitively awaits the whole chain. Avoid
        // flushPendingWrites here — its trailing force-save would write
        // editingTitle/editingBody (still T0/B0 from selectNote) and mask the
        // chain's final state.
        let lastID = try XCTUnwrap(viewModel.noteSavePendingID)
        let lastTask = try XCTUnwrap(viewModel.pendingWrites[lastID])
        await lastTask.value

        let saved = try await repository.fetchAll()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.title, "T3")
        XCTAssertEqual(saved.first?.body, "B3")
    }
}
