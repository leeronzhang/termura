import Foundation
import GRDB
import XCTest
@testable import Termura

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
