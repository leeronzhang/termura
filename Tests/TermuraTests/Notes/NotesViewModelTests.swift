import XCTest
@testable import Termura

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

    func testDeleteNoteRemovesFromList() {
        viewModel.createNote()
        let id = viewModel.notes[0].id
        viewModel.deleteNote(id: id)
        XCTAssertTrue(viewModel.notes.isEmpty)
    }

    func testDeleteSelectedNoteSelectsNext() {
        viewModel.createNote()
        viewModel.createNote()
        let firstID = viewModel.notes[0].id
        let secondID = viewModel.notes[1].id

        // Select the first, then delete it.
        viewModel.selectNote(id: firstID)
        viewModel.deleteNote(id: firstID)

        // Should auto-select the remaining note.
        XCTAssertEqual(viewModel.selectedNoteID, secondID)
    }

    func testDeleteOnlyNoteClearsSelection() {
        viewModel.createNote()
        let id = viewModel.notes[0].id
        viewModel.deleteNote(id: id)
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
}
