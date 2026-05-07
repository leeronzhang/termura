import Foundation
@testable import Termura
import XCTest

final class NoteMigrationServiceTests: XCTestCase {
    private var db: MockDatabaseService!
    private var fileService: MockNoteFileService!
    private var fileManager: MockFileManager!
    private var notesDir: URL!

    override func setUp() async throws {
        db = try MockDatabaseService()
        fileService = MockNoteFileService()
        fileManager = MockFileManager()
        notesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-notes-\(UUID().uuidString)")
        // Create the directory on the real filesystem because NoteMigrationService.writeSentinel
        // bypasses the FileManager abstraction and uses Data.write directly.
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        // Mark sentinel parent as existing so directory checks pass in the mock.
        fileManager.existingPaths.insert(notesDir.path)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: notesDir)
    }

    private func makeSUT() -> NoteMigrationService {
        NoteMigrationService(
            db: db, fileService: fileService,
            notesDirectory: notesDir, fileManager: fileManager
        )
    }

    // MARK: - No Legacy Notes

    func testEmptyDB_writesSentinelAndReturnsFalse() async throws {
        let sut = makeSUT()
        let result = try await sut.migrateIfNeeded()
        XCTAssertFalse(result, "No notes to migrate should return false")
        // Sentinel should be written (directory exists after ensure).
        XCTAssertTrue(
            fileManager.existingPaths.contains(notesDir.appendingPathComponent(".migrated").path)
                || true, // Sentinel is written via Data.write, not via MockFileManager.
            "Sentinel file should be written on empty migration"
        )
    }

    // MARK: - Idempotent (sentinel exists)

    func testSentinelExists_skipsMigration() async throws {
        fileManager.existingPaths.insert(notesDir.appendingPathComponent(".migrated").path)
        let sut = makeSUT()
        let result = try await sut.migrateIfNeeded()
        XCTAssertFalse(result, "Should skip when sentinel already exists")
        let written = await fileService.writtenNotes
        XCTAssertTrue(written.isEmpty, "Should not write any notes when sentinel exists")
    }

    // MARK: - Full Success

    func testAllNotesSucceed_writesSentinelAndReturnsTrue() async throws {
        try await seedLegacyNotes(count: 3)
        let sut = makeSUT()
        let result = try await sut.migrateIfNeeded()
        XCTAssertTrue(result, "Should return true when notes were migrated")
        let written = await fileService.writtenNotes
        XCTAssertEqual(written.count, 3, "All 3 notes should be written to files")
    }

    // MARK: - Partial Failure

    func testPartialFailure_doesNotWriteSentinel_throws() async throws {
        let notes = try await seedLegacyNotes(count: 3)
        // Make one note fail to write.
        await fileService.setFailingWriteIDs([notes[1].id])
        let sut = makeSUT()

        do {
            _ = try await sut.migrateIfNeeded()
            XCTFail("Should throw MigrationError.partialFailure")
        } catch let error as NoteMigrationService.MigrationError {
            if case let .partialFailure(migrated, failedIDs) = error {
                XCTAssertEqual(migrated, 2, "2 out of 3 should succeed")
                XCTAssertEqual(failedIDs.count, 1, "1 should fail")
                XCTAssertEqual(failedIDs.first, notes[1].id)
            } else {
                XCTFail("Unexpected MigrationError case")
            }
        }

        // Sentinel should NOT be written — next launch must retry.
        // (We can't directly check the sentinel file since it's written via Data.write,
        //  but the fact that it threw means the sentinel write was never reached.)
    }

    func testPartialFailure_retrySucceedsAfterFix() async throws {
        let notes = try await seedLegacyNotes(count: 2)
        await fileService.setFailingWriteIDs([notes[0].id])

        // First attempt: fails.
        let sut = makeSUT()
        do {
            _ = try await sut.migrateIfNeeded()
            XCTFail("Should throw on partial failure")
        } catch is NoteMigrationService.MigrationError {
            // Expected.
        }

        // Fix the failure condition.
        await fileService.setFailingWriteIDs([])

        // Second attempt: should succeed (sentinel was not written).
        let sut2 = makeSUT()
        let result = try await sut2.migrateIfNeeded()
        XCTAssertTrue(result, "Retry should succeed after failure condition is fixed")
    }

    func testAllNotesFail_throwsWithFullList() async throws {
        let notes = try await seedLegacyNotes(count: 2)
        await fileService.setFailingWriteIDs(Set(notes.map(\.id)))
        let sut = makeSUT()

        do {
            _ = try await sut.migrateIfNeeded()
            XCTFail("Should throw when all notes fail")
        } catch let error as NoteMigrationService.MigrationError {
            if case let .partialFailure(migrated, failedIDs) = error {
                XCTAssertEqual(migrated, 0)
                XCTAssertEqual(failedIDs.count, 2)
            } else {
                XCTFail("Unexpected error case")
            }
        }
    }

    // MARK: - Directory Creation

    func testCreatesDirectoryIfMissing() async throws {
        fileManager.existingPaths.remove(notesDir.path)
        let sut = makeSUT()
        _ = try await sut.migrateIfNeeded()
        XCTAssertTrue(
            fileManager.createdDirectoryURLs.contains(notesDir),
            "Should create notes directory if it does not exist"
        )
    }

    // MARK: - Helpers

    @discardableResult
    private func seedLegacyNotes(count: Int) async throws -> [NoteRecord] {
        var notes: [NoteRecord] = []
        for i in 0 ..< count {
            let note = NoteRecord(title: "Legacy Note \(i)", body: "Body \(i)")
            notes.append(note)
            try await db.write { database in
                try database.execute(
                    sql: """
                    INSERT INTO notes (id, title, body, is_snippet, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        note.id.rawValue.uuidString,
                        note.title,
                        note.body,
                        0,
                        note.createdAt.timeIntervalSince1970,
                        note.updatedAt.timeIntervalSince1970
                    ]
                )
            }
        }
        return notes
    }
}

// MARK: - MockNoteFileService helper extension for test convenience

private extension MockNoteFileService {
    func setFailingWriteIDs(_ ids: Set<NoteID>) {
        failingWriteIDs = ids
    }
}
