import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NoteRepository")

// MARK: - GRDB Row Adapter (private to this file)

private struct NoteRow: FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "notes"

    var id: String
    var title: String
    var body: String
    /// Maps to DB column `is_snippet` (legacy name, semantically "is_favorite").
    var isFavorite: Int
    var createdAt: Double
    var updatedAt: Double
    var archivedAt: Double?

    enum Columns: String, ColumnExpression {
        case id, title, body
        // DB column is `is_snippet` (legacy); semantically stores favorite flag.
        case isFavorite = "is_snippet"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archivedAt = "archived_at"
    }

    init(row: Row) throws {
        id = row[Columns.id]
        title = row[Columns.title]
        body = row[Columns.body]
        isFavorite = row[Columns.isFavorite]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
        archivedAt = row[Columns.archivedAt]
    }

    init(note: NoteRecord) {
        id = note.id.rawValue.uuidString
        title = note.title
        body = note.body
        isFavorite = note.isFavorite ? 1 : 0
        createdAt = note.createdAt.timeIntervalSince1970
        updatedAt = note.updatedAt.timeIntervalSince1970
        archivedAt = nil
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.title] = title
        container[Columns.body] = body
        container[Columns.isFavorite] = isFavorite
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
        container[Columns.archivedAt] = archivedAt
    }

    func toNote() throws -> NoteRecord {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.invalidID(rawValue: id, entity: "Note")
        }
        var note = NoteRecord(id: NoteID(rawValue: uuid), title: title, body: body, isFavorite: isFavorite != 0)
        note.createdAt = Date(timeIntervalSince1970: createdAt)
        note.updatedAt = Date(timeIntervalSince1970: updatedAt)
        return note
    }
}

// MARK: - Repository

actor NoteRepository: NoteRepositoryProtocol {
    private let db: any DatabaseServiceProtocol
    private let clock: any AppClock

    init(db: any DatabaseServiceProtocol, clock: any AppClock = LiveClock()) {
        self.db = db
        self.clock = clock
    }

    func fetchAll() async throws -> [NoteRecord] {
        try await db.read { database in
            let rows = try NoteRow
                .filter(sql: "archived_at IS NULL")
                .order(sql: "is_snippet DESC, updated_at DESC")
                .fetchAll(database)
            return try rows.map { try $0.toNote() }
        }
    }

    func save(_ note: NoteRecord) async throws {
        var mutable = NoteRow(note: note)
        mutable.updatedAt = clock.now().timeIntervalSince1970
        let row = mutable // immutable copy safe for @Sendable closure
        try await db.write { database in
            try row.save(database)
        }
    }

    func delete(id: NoteID) async throws {
        let idStr = id.rawValue.uuidString
        try await db.write { database in
            try database.execute(
                sql: "DELETE FROM notes WHERE id = ?",
                arguments: [idStr]
            )
        }
    }

    func search(query: String) async throws -> [NoteRecord] {
        guard query.count >= AppConfig.Search.minQueryLength else { return [] }
        let ftsQuery = FTS5.escapeQuery(query)
        return try await db.read { database in
            let rows = try NoteRow.fetchAll(
                database,
                sql: """
                SELECT n.* FROM notes n
                JOIN notes_fts fts ON n.rowid = fts.rowid
                WHERE notes_fts MATCH ? AND n.archived_at IS NULL
                ORDER BY rank LIMIT ?
                """,
                arguments: [ftsQuery, AppConfig.Search.maxResults]
            )
            return try rows.map { try $0.toNote() }
        }
    }
}
