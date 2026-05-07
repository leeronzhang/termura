import Foundation
import GRDB
@testable import Termura
import XCTest

final class DatabaseMigrationsTests: XCTestCase {
    private var dbService: MockDatabaseService!

    override func setUp() async throws {
        dbService = try MockDatabaseService()
    }

    // MARK: - Schema validation

    func testAllTablesExist() async throws {
        let tables = try await dbService.read { db -> Set<String> in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table'"
            )
            return Set(rows.map { $0["name"] as String })
        }

        let expected: Set<String> = [
            "sessions", "session_snapshots", "notes",
            "session_messages", "harness_events", "rule_files"
        ]
        for table in expected {
            XCTAssertTrue(tables.contains(table), "Missing table: \(table)")
        }
    }

    func testSessionsTableHasTreeColumns() async throws {
        let columns = try await dbService.read { db -> Set<String> in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(sessions)")
            return Set(rows.map { $0["name"] as String })
        }

        XCTAssertTrue(columns.contains("parent_id"), "Missing parent_id column")
        XCTAssertTrue(columns.contains("summary"), "Missing summary column")
        XCTAssertTrue(columns.contains("branch_type"), "Missing branch_type column")
    }

    func testFTSTablesExist() async throws {
        let tables = try await dbService.read { db -> Set<String> in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_fts'"
            )
            return Set(rows.map { $0["name"] as String })
        }

        XCTAssertTrue(tables.contains("sessions_fts"), "Missing sessions_fts")
        XCTAssertTrue(tables.contains("notes_fts"), "Missing notes_fts")
    }

    func testIndexesExist() async throws {
        let indexes = try await dbService.read { db -> Set<String> in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='index'"
            )
            return Set(rows.map { $0["name"] as String })
        }

        let expected = [
            "idx_sessions_order", "idx_sessions_parent",
            "idx_messages_session", "idx_harness_events_session",
            "idx_rule_files_path"
        ]
        for idx in expected {
            XCTAssertTrue(indexes.contains(idx), "Missing index: \(idx)")
        }
    }

    // MARK: - Real data migration (insert → query roundtrip)

    func testInsertAndQuerySessionRoundtrip() async throws {
        let repo = SessionRepository(db: dbService)
        let session = SessionRecord(
            title: "Migration Test",
            workingDirectory: "/tmp/test",
            orderIndex: 0
        )
        try await repo.save(session)

        let loaded = try await repo.fetchAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Migration Test")
        XCTAssertEqual(loaded.first?.workingDirectory, "/tmp/test")
    }

    func testInsertNoteWithFTSSearch() async throws {
        let repo = NoteRepository(db: dbService)
        let note = NoteRecord(title: "Search Target", body: "findable content here")
        try await repo.save(note)

        let results = try await repo.search(query: "findable")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Search Target")
    }

    func testSessionBranchCreation() async throws {
        let repo = SessionRepository(db: dbService)
        let parent = SessionRecord(title: "Parent", orderIndex: 0)
        try await repo.save(parent)

        let branch = try await repo.createBranch(
            from: parent.id, type: .experiment, title: "Child Branch"
        )
        XCTAssertEqual(branch.parentID, parent.id)
        XCTAssertEqual(branch.branchType, .experiment)

        let children = try await repo.fetchChildren(of: parent.id)
        XCTAssertEqual(children.count, 1)
    }

    func testAgentTypeColumnMigration() async throws {
        let repo = SessionRepository(db: dbService)
        var session = SessionRecord(title: "Agent Test", orderIndex: 0)
        session.agentType = .claudeCode
        try await repo.save(session)

        let loaded = try await repo.fetchAll()
        XCTAssertEqual(loaded.first?.agentType, .claudeCode)
    }

    // MARK: - Foreign key cascades

    func testDeleteSessionCascadesSnapshots() async throws {
        let sessionRepo = SessionRepository(db: dbService)
        let snapshotRepo = SessionSnapshotRepository(db: dbService)

        let session = SessionRecord(title: "Cascade Test")
        try await sessionRepo.save(session)
        try await snapshotRepo.save(lines: ["test line"], for: session.id)

        // Verify snapshot exists.
        let before = try await snapshotRepo.load(for: session.id)
        XCTAssertNotNil(before)

        // Delete the session — cascade should remove snapshot.
        try await sessionRepo.delete(id: session.id)
        let after = try await snapshotRepo.load(for: session.id)
        XCTAssertNil(after)
    }

    // MARK: - Per-step migration trigger tests

    /// v2: AFTER INSERT trigger on sessions must populate sessions_fts.
    func testV2FTSTriggerInsert() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(queue, upTo: "v2_sessions_fts")

        let now = Date().timeIntervalSince1970
        let id = UUID().uuidString
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO sessions(id,title,working_directory,created_at,last_active_at,
                                     color_label,is_pinned,order_index)
                VALUES(?,?,?,?,?,?,?,?)
                """,
                arguments: [id, "TriggerInsertTitle", "/tmp", now, now, "none", false, 0]
            )
        }

        let count = try queue.read { db -> Int in
            try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM sessions_fts WHERE sessions_fts MATCH ?",
                arguments: ["TriggerInsertTitle"]
            ) ?? 0
        }
        XCTAssertEqual(count, 1, "AFTER INSERT trigger must populate sessions_fts")
    }

    /// v2: AFTER UPDATE and AFTER DELETE triggers must update and remove sessions_fts entries.
    func testV2FTSTriggerUpdateAndDelete() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(queue, upTo: "v2_sessions_fts")

        let now = Date().timeIntervalSince1970
        let id = UUID().uuidString
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO sessions(id,title,working_directory,created_at,last_active_at,
                                     color_label,is_pinned,order_index)
                VALUES(?,?,?,?,?,?,?,?)
                """,
                arguments: [id, "OldTitle", "/tmp", now, now, "none", false, 0]
            )
            // AFTER UPDATE: new title must appear, old title must disappear.
            try db.execute(
                sql: "UPDATE sessions SET title = ? WHERE id = ?",
                arguments: ["NewTitle", id]
            )
        }

        let afterUpdate = try queue.read { db -> (old: Int, new: Int) in
            let old = try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM sessions_fts WHERE sessions_fts MATCH ?",
                arguments: ["OldTitle"]
            ) ?? 0
            let new = try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM sessions_fts WHERE sessions_fts MATCH ?",
                arguments: ["NewTitle"]
            ) ?? 0
            return (old, new)
        }
        XCTAssertEqual(afterUpdate.old, 0, "Old title must be removed from FTS after UPDATE")
        XCTAssertEqual(afterUpdate.new, 1, "New title must appear in FTS after UPDATE")

        try queue.write { db in
            try db.execute(sql: "DELETE FROM sessions WHERE id = ?", arguments: [id])
        }

        let afterDelete = try queue.read { db -> Int in
            try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM sessions_fts WHERE sessions_fts MATCH ?",
                arguments: ["NewTitle"]
            ) ?? 0
        }
        XCTAssertEqual(afterDelete, 0, "FTS entry must be removed after DELETE")
    }

    /// v4: AFTER INSERT trigger on notes must populate notes_fts.
    func testV4NotesFTSTriggerInsert() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(queue, upTo: "v4_notes")

        let now = Date().timeIntervalSince1970
        let id = UUID().uuidString
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO notes(id,title,body,created_at,updated_at)
                VALUES(?,?,?,?,?)
                """,
                arguments: [id, "NoteInsertTitle", "NoteInsertBody", now, now]
            )
        }

        let count = try queue.read { db -> Int in
            try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["NoteInsertTitle"]
            ) ?? 0
        }
        XCTAssertEqual(count, 1, "AFTER INSERT trigger must populate notes_fts")
    }

    /// v4: AFTER UPDATE and AFTER DELETE triggers must update and remove notes_fts entries.
    func testV4NotesFTSTriggerUpdateAndDelete() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(queue, upTo: "v4_notes")

        let now = Date().timeIntervalSince1970
        let id = UUID().uuidString
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO notes(id,title,body,created_at,updated_at) VALUES(?,?,?,?,?)",
                arguments: [id, "OriginalNote", "OriginalBody", now, now]
            )
            try db.execute(
                sql: "UPDATE notes SET body = ? WHERE id = ?",
                arguments: ["UpdatedBody", id]
            )
        }

        let afterUpdate = try queue.read { db -> (old: Int, new: Int) in
            let old = try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["OriginalBody"]
            ) ?? 0
            let new = try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["UpdatedBody"]
            ) ?? 0
            return (old, new)
        }
        XCTAssertEqual(afterUpdate.old, 0, "Old body must be removed from notes_fts after UPDATE")
        XCTAssertEqual(afterUpdate.new, 1, "Updated body must appear in notes_fts after UPDATE")

        try queue.write { db in
            try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [id])
        }

        let afterDelete = try queue.read { db -> Int in
            try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["UpdatedBody"]
            ) ?? 0
        }
        XCTAssertEqual(afterDelete, 0, "notes_fts entry must be removed after DELETE")
    }

    /// v8: New note rows must default is_snippet to 0 (false) when not specified.
    func testV8IsSnippetDefaultValue() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(queue, upTo: "v8_snippets")

        let now = Date().timeIntervalSince1970
        let id = UUID().uuidString
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO notes(id,title,body,created_at,updated_at) VALUES(?,?,?,?,?)",
                arguments: [id, "DefaultSnippet", "body", now, now]
            )
        }

        let isSnippet = try queue.read { db -> Int in
            try Int.fetchOne(
                db,
                sql: "SELECT is_snippet FROM notes WHERE id = ?",
                arguments: [id]
            ) ?? -1
        }
        XCTAssertEqual(isSnippet, 0, "is_snippet must default to 0 for new notes")
    }

    /// v9: New session rows must default ended_at to NULL.
    func testV9EndedAtNullForNewSessions() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(queue, upTo: "v9_session_ended_at")

        let now = Date().timeIntervalSince1970
        let id = UUID().uuidString
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO sessions(id,title,working_directory,created_at,last_active_at,
                                     color_label,is_pinned,order_index)
                VALUES(?,?,?,?,?,?,?,?)
                """,
                arguments: [id, "EndedAtDefault", "/tmp", now, now, "none", false, 0]
            )
        }

        let endedAt = try queue.read { db -> DatabaseValue in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT ended_at FROM sessions WHERE id = ?",
                arguments: [id]
            )
            return row?["ended_at"] ?? DatabaseValue.null
        }
        XCTAssertTrue(endedAt.isNull, "ended_at must be NULL for new sessions")
    }

    /// v9: markEnded sets a non-null timestamp; markReopened clears it.
    func testV9EndedAtPersistsAfterMarkEnded() async throws {
        let repo = SessionRepository(db: dbService)
        let session = SessionRecord(title: "MarkEnded Test")
        try await repo.save(session)

        let stamp = Date()
        try await repo.markEnded(id: session.id, at: stamp)

        let loaded = try await repo.fetchAll()
        XCTAssertNotNil(loaded.first?.endedAt, "endedAt must be set after markEnded")
        if let endedAt = loaded.first?.endedAt {
            XCTAssertLessThanOrEqual(
                abs(endedAt.timeIntervalSince(stamp)),
                1.0,
                "endedAt must be within 1s of the provided stamp"
            )
        }
    }

    func testV9EndedAtClearsAfterMarkReopened() async throws {
        let repo = SessionRepository(db: dbService)
        let session = SessionRecord(title: "MarkReopened Test")
        try await repo.save(session)

        try await repo.markEnded(id: session.id, at: Date())
        try await repo.markReopened(id: session.id)

        let loaded = try await repo.fetchAll()
        XCTAssertNil(loaded.first?.endedAt, "endedAt must be nil after markReopened")
    }

    func testDeleteSessionCascadesMessages() async throws {
        let sessionRepo = SessionRepository(db: dbService)
        let msgRepo = SessionMessageRepository(db: dbService)

        let session = SessionRecord(title: "Cascade Test")
        try await sessionRepo.save(session)
        let msg = SessionMessage(
            sessionID: session.id,
            role: .user,
            contentType: .model,
            content: "test"
        )
        try await msgRepo.save(msg)

        // Verify message exists.
        let before = try await msgRepo.fetchMessages(for: session.id, contentType: nil)
        XCTAssertEqual(before.count, 1)

        // Delete the session — cascade should remove messages.
        try await sessionRepo.delete(id: session.id)
        let after = try await msgRepo.fetchMessages(for: session.id, contentType: nil)
        XCTAssertTrue(after.isEmpty)
    }
}
