import Foundation
@testable import Termura
import XCTest

final class FileBackedNoteRepositoryTests: XCTestCase {
    private var db: MockDatabaseService!
    private var fileService: MockNoteFileService!
    private var fileManager: MockFileManager!
    private var notesDir: URL!

    override func setUp() async throws {
        db = try MockDatabaseService()
        fileService = MockNoteFileService()
        fileManager = MockFileManager()
        notesDir = URL(fileURLWithPath: "/tmp/test-notes-\(UUID().uuidString)")
        fileManager.existingPaths.insert(notesDir.path)
    }

    private func makeSUT() -> FileBackedNoteRepository {
        FileBackedNoteRepository(
            notesDirectory: notesDir,
            fileService: fileService,
            db: db,
            fileManager: fileManager
        )
    }

    // MARK: - Basic CRUD

    func testSaveAndFetchAll() async throws {
        let sut = makeSUT()
        let note = NoteRecord(title: "Test", body: "Body")
        try await sut.save(note)
        let all = try await sut.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, note.id)
        XCTAssertEqual(all.first?.title, "Test")
    }

    func testDeleteRemovesNote() async throws {
        let sut = makeSUT()
        let note = NoteRecord(title: "Test", body: "Body")
        try await sut.save(note)
        try await sut.delete(id: note.id)
        let all = try await sut.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Rename Atomicity (Issue #2)

    func testRename_oldDeleteFails_saveThrows() async throws {
        let sut = makeSUT()
        let note = NoteRecord(title: "Original", body: "Body")
        try await sut.save(note)

        // Get the URL of the existing file.
        let originalURL = notesDir.appendingPathComponent(NoteFileService.filename(for: note))
        await fileService.setFailingDeleteURL(originalURL)

        // Rename the note (changes title → changes filename).
        var renamed = note
        renamed.title = "Renamed Title"

        do {
            try await sut.save(renamed)
            XCTFail("Save should throw when old file deletion fails")
        } catch {
            // Expected: old file delete failure propagates.
        }

        // Verify: no duplicate file was created.
        let written = await fileService.writtenNotes
        // The original file should still be the only one (delete failed, new file not written).
        XCTAssertEqual(written.count, 1, "Should not create duplicate file on rename failure")
    }

    func testRename_sameTitle_noDeleteAttempted() async throws {
        let sut = makeSUT()
        let note = NoteRecord(title: "Stable", body: "Body")
        try await sut.save(note)

        // Save again with same title but different body — no rename needed.
        var updated = note
        updated.body = "Updated body"
        try await sut.save(updated)

        let all = try await sut.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.body, "Updated body")
    }

    // MARK: - Incremental Sync

    func testIncrementalSync_newFile_addedToIndex() async throws {
        let sut = makeSUT()
        // Initial load with one note.
        let note1 = NoteRecord(title: "First", body: "Body 1")
        try await sut.save(note1)

        // Simulate external addition: write a new file directly via fileService.
        let note2 = NoteRecord(title: "External", body: "Added externally")
        let url2 = notesDir.appendingPathComponent(NoteFileService.filename(for: note2))
        await fileService.injectNote(note2, at: url2)

        // Trigger reload from disk (simulates what incrementalSync does).
        try await sut.reloadFromDisk()

        let all = try await sut.fetchAll()
        XCTAssertEqual(all.count, 2, "Should include both original and externally added note")
        XCTAssertTrue(all.contains(where: { $0.id == note2.id }))
    }

    func testIncrementalSync_deletedFile_removedFromIndex() async throws {
        let sut = makeSUT()
        let note = NoteRecord(title: "WillBeDeleted", body: "Body")
        try await sut.save(note)

        // Simulate external deletion: remove from fileService's store.
        let url = notesDir.appendingPathComponent(NoteFileService.filename(for: note))
        await fileService.removeNote(at: url)

        // Reload from disk.
        try await sut.reloadFromDisk()

        let all = try await sut.fetchAll()
        XCTAssertTrue(all.isEmpty, "Externally deleted note should be removed from index")
    }

    // MARK: - Sort Order

    func testFetchAll_favoritesFirst_thenByUpdatedAt() async throws {
        let sut = makeSUT()
        let old = NoteRecord(title: "Old", body: "")
        let newer = NoteRecord(title: "Newer", body: "")
        var fav = NoteRecord(title: "Favorite", body: "")
        fav.isFavorite = true

        try await sut.save(old)
        try await sut.save(newer)
        try await sut.save(fav)

        let all = try await sut.fetchAll()
        XCTAssertEqual(all.first?.id, fav.id, "Favorite should be first")
    }

    // MARK: - Lifecycle Protocol

    func testStartStopWatching_doesNotCrash() async throws {
        let sut = makeSUT()
        // startWatching needs a real directory to open() — skip in unit test.
        // Just verify stopWatching is safe to call without prior start.
        await sut.stopWatching()
    }

    // MARK: - Relationship Sync (v10)

    func testSavingNoteWithWikiLinkPopulatesNoteLinks() async throws {
        let sut = makeSUT()
        let note = NoteRecord(title: "Source", body: "Refers to [[OtherNote]] for detail.")
        try await sut.save(note)

        let backlinks = try await sut.backlinks(toTitle: "OtherNote")
        XCTAssertEqual(backlinks.count, 1)
        XCTAssertEqual(backlinks.first?.id, note.id)
    }

    func testSavingNoteWithTagsPopulatesNoteTags() async throws {
        let sut = makeSUT()
        var note = NoteRecord(title: "T", body: "")
        note.tags = ["alpha", "beta"]
        try await sut.save(note)

        let alphaNotes = try await sut.notes(taggedWith: "alpha")
        XCTAssertEqual(alphaNotes.count, 1)
        XCTAssertEqual(alphaNotes.first?.id, note.id)

        let betaNotes = try await sut.notes(taggedWith: "beta")
        XCTAssertEqual(betaNotes.count, 1)
    }

    func testDeletingNoteRemovesRelations() async throws {
        let sut = makeSUT()
        var note = NoteRecord(title: "T", body: "Refers [[X]]")
        note.tags = ["alpha"]
        try await sut.save(note)

        try await sut.delete(id: note.id)

        let backlinks = try await sut.backlinks(toTitle: "X")
        XCTAssertTrue(backlinks.isEmpty, "Wiki-link rows must be cleared on delete")
        let tagged = try await sut.notes(taggedWith: "alpha")
        XCTAssertTrue(tagged.isEmpty, "Tag rows must be cleared on delete")
    }

    func testUpdatingNoteReplacesOldRelations() async throws {
        let sut = makeSUT()
        var note = NoteRecord(title: "T", body: "Old body [[Old]]")
        note.tags = ["old"]
        try await sut.save(note)

        // Update body to remove old link, add new one.
        var updated = note
        updated.body = "New body [[New]]"
        updated.tags = ["new"]
        try await sut.save(updated)

        let oldBacklinks = try await sut.backlinks(toTitle: "Old")
        XCTAssertTrue(oldBacklinks.isEmpty, "Old link should be removed")
        let newBacklinks = try await sut.backlinks(toTitle: "New")
        XCTAssertEqual(newBacklinks.count, 1, "New link should be inserted")

        let oldTagged = try await sut.notes(taggedWith: "old")
        XCTAssertTrue(oldTagged.isEmpty)
        let newTagged = try await sut.notes(taggedWith: "new")
        XCTAssertEqual(newTagged.count, 1)
    }

    func testBacklinkLookupIsCaseInsensitive() async throws {
        let sut = makeSUT()
        let note = NoteRecord(title: "T", body: "Mentions [[MyNote]]")
        try await sut.save(note)
        let lower = try await sut.backlinks(toTitle: "mynote")
        XCTAssertEqual(lower.count, 1)
        let upper = try await sut.backlinks(toTitle: "MYNOTE")
        XCTAssertEqual(upper.count, 1)
    }
}

// MARK: - MockNoteFileService helper extensions for test convenience

private extension MockNoteFileService {
    func setFailingDeleteURL(_ url: URL) {
        failingDeleteURLs.insert(url)
    }

    func injectNote(_ note: NoteRecord, at url: URL) {
        writtenNotes[url] = note
    }

    func removeNote(at url: URL) {
        writtenNotes.removeValue(forKey: url)
    }
}
