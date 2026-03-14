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
