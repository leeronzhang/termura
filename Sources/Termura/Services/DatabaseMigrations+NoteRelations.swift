import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "DatabaseMigrations.NoteRelations")

// MARK: - Note relationship migrations

//
// Split out of DatabaseMigrations.swift to keep that file under the size budget.
// v10 added note_links / note_file_references / note_tags as derived indexes
// of note frontmatter + body. v11 drops note_file_references after the
// knowledge layer was scoped down to notes-only.

extension DatabaseMigrations {
    /// Adds derived-relationship tables synced from note frontmatter + body
    /// on every note save. These power Backlinks UI and tag filtering without
    /// scanning every note in memory. Source of truth lives in the .md files;
    /// these are rebuildable indexes.
    static func registerV10NoteRelationships(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v10_note_relationships") { db in
            try db.execute(sql: """
            CREATE TABLE note_links (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                from_note_id TEXT NOT NULL,
                to_note_title TEXT NOT NULL,
                link_kind TEXT NOT NULL,
                UNIQUE(from_note_id, to_note_title, link_kind)
            )
            """)
            try db.execute(sql: "CREATE INDEX idx_note_links_from ON note_links(from_note_id)")
            try db.execute(sql: "CREATE INDEX idx_note_links_to ON note_links(to_note_title)")

            try db.execute(sql: """
            CREATE TABLE note_file_references (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                note_id TEXT NOT NULL,
                project_file_path TEXT NOT NULL,
                mention_count INTEGER NOT NULL,
                UNIQUE(note_id, project_file_path)
            )
            """)
            try db.execute(sql: """
            CREATE INDEX idx_note_file_refs_file ON note_file_references(project_file_path)
            """)
            try db.execute(sql: "CREATE INDEX idx_note_file_refs_note ON note_file_references(note_id)")

            try db.execute(sql: """
            CREATE TABLE note_tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                note_id TEXT NOT NULL,
                tag TEXT NOT NULL,
                UNIQUE(note_id, tag)
            )
            """)
            try db.execute(sql: "CREATE INDEX idx_note_tags_tag ON note_tags(tag)")
            try db.execute(sql: "CREATE INDEX idx_note_tags_note ON note_tags(note_id)")

            logger.info("v10 migration complete: note_links / note_file_references / note_tags tables")
        }
    }

    /// Drops `note_file_references` and its indexes. The note → project-file
    /// mention concept turned out to be premature — Termura's notes layer is
    /// now scoped to in-note relations (wiki-link backlinks + tags). The
    /// table only ever held shipped-but-unused data; safe to drop.
    static func registerV11DropNoteFileReferences(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v11_drop_note_file_references") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS note_file_references")
            // Indexes dropped automatically with the table.
            logger.info("v11 migration complete: dropped note_file_references")
        }
    }
}
