import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "FileBackedNoteRepository.Relations")

// MARK: - Note relationship sync (derived tables)

//
// `note_links` / `note_file_references` / `note_tags` are kept in lock-step
// with note files on disk. The .md frontmatter + body remain the source of
// truth; these tables are a rebuilt index used by Backlinks UI, file-mention
// lookups, and future CLI/MCP queries.
//
// Each upsertCache(note) → re-derives all three sets for the note and replaces
// the rows. deleteCache(id) drops them. Migrated in v10 (DatabaseMigrations.swift).

extension FileBackedNoteRepository {
    /// Replaces all relation rows for `note` with freshly extracted ones.
    /// Called from `upsertCache(_:)` after the main `notes` row is written.
    func syncRelationsForNote(_ note: NoteRecord, projectRoot: URL?) async throws {
        let id = note.id.rawValue.uuidString
        let titleLinks = WikiLinkExtractor.extract(from: note.body)
        let fileRefs: [ProjectFileReference] = projectRoot.map { root in
            ProjectFileReferenceExtractor.extract(from: note.body, projectRoot: root)
        } ?? []
        let tags = note.tags
        let compiledFromLinks = note.references // frontmatter `references:` doubles as compiled_from for v1

        try await db.write { db in
            try db.execute(sql: "DELETE FROM note_links WHERE from_note_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM note_file_references WHERE note_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM note_tags WHERE note_id = ?", arguments: [id])

            for target in titleLinks {
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO note_links (from_note_id, to_note_title, link_kind)
                    VALUES (?, ?, 'wikilink')
                    """,
                    arguments: [id, target]
                )
            }
            for ref in compiledFromLinks {
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO note_links (from_note_id, to_note_title, link_kind)
                    VALUES (?, ?, 'compiled_from')
                    """,
                    arguments: [id, ref]
                )
            }
            for ref in fileRefs {
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO note_file_references
                        (note_id, project_file_path, mention_count)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [id, ref.projectFilePath, ref.mentionCount]
                )
            }
            for tag in tags {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                try db.execute(
                    sql: "INSERT OR IGNORE INTO note_tags (note_id, tag) VALUES (?, ?)",
                    arguments: [id, trimmed]
                )
            }
        }
    }

    /// Drops all relation rows for the given note id. Called from `deleteCache(id:)`.
    func deleteRelationsForNote(id: NoteID) async throws {
        let idStr = id.rawValue.uuidString
        try await db.write { db in
            try db.execute(sql: "DELETE FROM note_links WHERE from_note_id = ?", arguments: [idStr])
            try db.execute(sql: "DELETE FROM note_file_references WHERE note_id = ?", arguments: [idStr])
            try db.execute(sql: "DELETE FROM note_tags WHERE note_id = ?", arguments: [idStr])
        }
    }

    // MARK: - Query API (NoteRepositoryProtocol)

    func backlinks(toTitle title: String) async throws -> [NoteRecord] {
        let lowered = title.lowercased()
        let ids: [String] = try await db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT DISTINCT from_note_id FROM note_links
                WHERE LOWER(to_note_title) = ?
                """,
                arguments: [lowered]
            )
            .compactMap { $0["from_note_id"] }
        }
        return resolveRecords(forNoteIDs: ids)
    }

    func notes(mentioningProjectFile path: String) async throws -> [NoteRecord] {
        let ids: [String] = try await db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT DISTINCT note_id FROM note_file_references WHERE project_file_path = ?",
                arguments: [path]
            )
            .compactMap { $0["note_id"] }
        }
        return resolveRecords(forNoteIDs: ids)
    }

    func notes(taggedWith tag: String) async throws -> [NoteRecord] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let ids: [String] = try await db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT DISTINCT note_id FROM note_tags WHERE tag = ?",
                arguments: [trimmed]
            )
            .compactMap { $0["note_id"] }
        }
        return resolveRecords(forNoteIDs: ids)
    }

    // MARK: - Private

    private func resolveRecords(forNoteIDs ids: [String]) -> [NoteRecord] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        return index.values
            .map(\.record)
            .filter { idSet.contains($0.id.rawValue.uuidString) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
