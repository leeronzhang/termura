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
        registerV7AgentType(into: &migrator)
        registerV8Snippets(into: &migrator)
    }

    // MARK: - v1: sessions table

    private static func registerV1Sessions(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_sessions") { db in
            try db.create(table: "sessions") { table in
                table.primaryKey("id", .text).notNull()
                table.column("title", .text).notNull().defaults(to: "Terminal")
                table.column("working_directory", .text).notNull().defaults(to: "")
                table.column("created_at", .double).notNull()
                table.column("last_active_at", .double).notNull()
                table.column("color_label", .text).notNull().defaults(to: "none")
                table.column("is_pinned", .boolean).notNull().defaults(to: false)
                table.column("order_index", .integer).notNull().defaults(to: 0)
                table.column("archived_at", .double)
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
            try db.create(table: "session_snapshots") { table in
                table.primaryKey("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                table.column("compressed_data", .blob).notNull()
                table.column("line_count", .integer).notNull().defaults(to: 0)
                table.column("saved_at", .double).notNull()
            }
        }
    }

    // MARK: - v4: notes + FTS5

    private static func registerV4Notes(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4_notes") { db in
            try db.create(table: "notes") { table in
                table.primaryKey("id", .text).notNull()
                table.column("title", .text).notNull().defaults(to: "")
                table.column("body", .text).notNull().defaults(to: "")
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
                table.column("archived_at", .double)
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

    // MARK: - v5: session tree + messages + harness events

    private static func registerV5SessionTree(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5_session_tree") { db in
            // Add tree columns to sessions
            try db.alter(table: "sessions") { table in
                table.add(column: "parent_id", .text)
                    .references("sessions")
                table.add(column: "summary", .text)
                    .notNull()
                    .defaults(to: "")
                table.add(column: "branch_type", .text)
                    .notNull()
                    .defaults(to: "main")
            }
            try db.create(
                index: "idx_sessions_parent",
                on: "sessions",
                columns: ["parent_id"]
            )

            // Messages table (dual-track: model / metadata / ui)
            try db.create(table: "session_messages") { table in
                table.primaryKey("id", .text).notNull()
                table.column("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                table.column("role", .text).notNull()
                table.column("content_type", .text).notNull()
                table.column("content", .text).notNull()
                table.column("token_count", .integer).defaults(to: 0)
                table.column("created_at", .double).notNull()
            }
            try db.create(
                index: "idx_messages_session",
                on: "session_messages",
                columns: ["session_id", "created_at"]
            )

            // Harness events table
            try db.create(table: "harness_events") { table in
                table.primaryKey("id", .text).notNull()
                table.column("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                table.column("event_type", .text).notNull()
                table.column("payload", .text).notNull()
                table.column("created_at", .double).notNull()
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
            try db.create(table: "rule_files") { table in
                table.primaryKey("id", .text).notNull()
                table.column("file_path", .text).notNull()
                table.column("content", .text).notNull()
                table.column("content_hash", .text).notNull()
                table.column("session_id", .text)
                    .references("sessions")
                table.column("version", .integer).notNull().defaults(to: 1)
                table.column("created_at", .double).notNull()
            }
            try db.create(
                index: "idx_rule_files_path",
                on: "rule_files",
                columns: ["file_path", "version"]
            )
            logger.info("v6 migration complete: rule_files table")
        }
    }

    // MARK: - v7: agent type on sessions

    private static func registerV7AgentType(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7_agent_type") { db in
            try db.alter(table: "sessions") { table in
                table.add(column: "agent_type", .text)
                    .notNull()
                    .defaults(to: "unknown")
            }
            logger.info("v7 migration complete: agent_type column")
        }
    }

    // MARK: - v8: notes favorite flag (column named is_snippet for legacy compat)

    private static func registerV8Snippets(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v8_snippets") { db in
            try db.alter(table: "notes") { table in
                table.add(column: "is_snippet", .integer)
                    .notNull()
                    .defaults(to: 0)
            }
            logger.info("v8 migration complete: is_snippet (favorite) column on notes")
        }
    }

}
