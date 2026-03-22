import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "DatabaseMigrations")

enum DatabaseMigrations {
    static func register(into migrator: inout DatabaseMigrator) {
        registerV1Sessions(into: &migrator)
        registerV2SessionsFTS(into: &migrator)
        registerV3Snapshots(into: &migrator)
        registerV4Notes(into: &migrator)
        registerV5SessionTree(into: &migrator)
        registerV6RuleFiles(into: &migrator)
    }

    // MARK: - v1: sessions table

    private static func registerV1Sessions(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_sessions") { db in
            try db.create(table: "sessions") { t in
                t.primaryKey("id", .text).notNull()
                t.column("title", .text).notNull().defaults(to: "Terminal")
                t.column("working_directory", .text).notNull().defaults(to: "")
                t.column("created_at", .double).notNull()
                t.column("last_active_at", .double).notNull()
                t.column("color_label", .text).notNull().defaults(to: "none")
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("order_index", .integer).notNull().defaults(to: 0)
                t.column("archived_at", .double)
            }
            try db.create(
                index: "idx_sessions_order",
                on: "sessions",
                columns: ["is_pinned", "order_index"]
            )
        }
    }

    // MARK: - v2: sessions FTS5

    private static func registerV2SessionsFTS(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_sessions_fts") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE sessions_fts USING fts5(
                    id UNINDEXED, title, working_directory,
                    content="sessions", content_rowid="rowid"
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER sessions_ai AFTER INSERT ON sessions BEGIN
                    INSERT INTO sessions_fts(rowid,id,title,working_directory)
                    VALUES(new.rowid,new.id,new.title,new.working_directory);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER sessions_ad AFTER DELETE ON sessions BEGIN
                    INSERT INTO sessions_fts(sessions_fts,rowid,id,title,working_directory)
                    VALUES('delete',old.rowid,old.id,old.title,old.working_directory);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER sessions_au AFTER UPDATE ON sessions BEGIN
                    INSERT INTO sessions_fts(sessions_fts,rowid,id,title,working_directory)
                    VALUES('delete',old.rowid,old.id,old.title,old.working_directory);
                    INSERT INTO sessions_fts(rowid,id,title,working_directory)
                    VALUES(new.rowid,new.id,new.title,new.working_directory);
                END
                """)
        }
    }

    // MARK: - v3: session snapshots

    private static func registerV3Snapshots(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_snapshots") { db in
            try db.create(table: "session_snapshots") { t in
                t.primaryKey("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("compressed_data", .blob).notNull()
                t.column("line_count", .integer).notNull().defaults(to: 0)
                t.column("saved_at", .double).notNull()
            }
        }
    }

    // MARK: - v5: session tree + messages + harness events

    private static func registerV5SessionTree(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5_session_tree") { db in
            // Add tree columns to sessions
            try db.alter(table: "sessions") { t in
                t.add(column: "parent_id", .text)
                    .references("sessions")
                t.add(column: "summary", .text)
                    .notNull()
                    .defaults(to: "")
                t.add(column: "branch_type", .text)
                    .notNull()
                    .defaults(to: "main")
            }
            try db.create(
                index: "idx_sessions_parent",
                on: "sessions",
                columns: ["parent_id"]
            )

            // Messages table (dual-track: model / metadata / ui)
            try db.create(table: "session_messages") { t in
                t.primaryKey("id", .text).notNull()
                t.column("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content_type", .text).notNull()
                t.column("content", .text).notNull()
                t.column("token_count", .integer).defaults(to: 0)
                t.column("created_at", .double).notNull()
            }
            try db.create(
                index: "idx_messages_session",
                on: "session_messages",
                columns: ["session_id", "created_at"]
            )

            // Harness events table
            try db.create(table: "harness_events") { t in
                t.primaryKey("id", .text).notNull()
                t.column("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("event_type", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("created_at", .double).notNull()
            }
            try db.create(
                index: "idx_harness_events_session",
                on: "harness_events",
                columns: ["session_id", "created_at"]
            )

            logger.info("v5 migration complete: session tree + messages + harness events")
        }
    }

    // MARK: - v6: rule files (Harness management)

    private static func registerV6RuleFiles(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v6_rule_files") { db in
            try db.create(table: "rule_files") { t in
                t.primaryKey("id", .text).notNull()
                t.column("file_path", .text).notNull()
                t.column("content", .text).notNull()
                t.column("content_hash", .text).notNull()
                t.column("session_id", .text)
                    .references("sessions")
                t.column("version", .integer).notNull().defaults(to: 1)
                t.column("created_at", .double).notNull()
            }
            try db.create(
                index: "idx_rule_files_path",
                on: "rule_files",
                columns: ["file_path", "version"]
            )
            logger.info("v6 migration complete: rule_files table")
        }
    }

    // MARK: - v4: notes + FTS5

    private static func registerV4Notes(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4_notes") { db in
            try db.create(table: "notes") { t in
                t.primaryKey("id", .text).notNull()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("body", .text).notNull().defaults(to: "")
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
                t.column("archived_at", .double)
            }
            try db.create(index: "idx_notes_updated", on: "notes", columns: ["updated_at"])
            try db.execute(sql: """
                CREATE VIRTUAL TABLE notes_fts USING fts5(
                    id UNINDEXED, title, body,
                    content="notes", content_rowid="rowid"
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
                    INSERT INTO notes_fts(rowid,id,title,body)
                    VALUES(new.rowid,new.id,new.title,new.body);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
                    INSERT INTO notes_fts(notes_fts,rowid,id,title,body)
                    VALUES('delete',old.rowid,old.id,old.title,old.body);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
                    INSERT INTO notes_fts(notes_fts,rowid,id,title,body)
                    VALUES('delete',old.rowid,old.id,old.title,old.body);
                    INSERT INTO notes_fts(rowid,id,title,body)
                    VALUES(new.rowid,new.id,new.title,new.body);
                END
                """)
        }
    }
}
