import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionRepository")

// MARK: - GRDB Row Adapter (private to this file)

private struct SessionRow: FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sessions"

    var id: String
    var title: String
    var workingDirectory: String
    var createdAt: Double
    var lastActiveAt: Double
    var colorLabel: String
    var isPinned: Bool
    var orderIndex: Int
    var archivedAt: Double?

    enum Columns: String, ColumnExpression {
        case id, title
        case workingDirectory = "working_directory"
        case createdAt = "created_at"
        case lastActiveAt = "last_active_at"
        case colorLabel = "color_label"
        case isPinned = "is_pinned"
        case orderIndex = "order_index"
        case archivedAt = "archived_at"
    }

    init(row: Row) throws {
        id = row[Columns.id]
        title = row[Columns.title]
        workingDirectory = row[Columns.workingDirectory]
        createdAt = row[Columns.createdAt]
        lastActiveAt = row[Columns.lastActiveAt]
        colorLabel = row[Columns.colorLabel]
        isPinned = row[Columns.isPinned]
        orderIndex = row[Columns.orderIndex]
        archivedAt = row[Columns.archivedAt]
    }

    init(record: SessionRecord, archivedAt: Date? = nil) {
        id = record.id.rawValue.uuidString
        title = record.title
        workingDirectory = record.workingDirectory
        createdAt = record.createdAt.timeIntervalSince1970
        lastActiveAt = record.lastActiveAt.timeIntervalSince1970
        colorLabel = record.colorLabel.rawValue
        isPinned = record.isPinned
        orderIndex = record.orderIndex
        self.archivedAt = archivedAt?.timeIntervalSince1970
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.title] = title
        container[Columns.workingDirectory] = workingDirectory
        container[Columns.createdAt] = createdAt
        container[Columns.lastActiveAt] = lastActiveAt
        container[Columns.colorLabel] = colorLabel
        container[Columns.isPinned] = isPinned
        container[Columns.orderIndex] = orderIndex
        container[Columns.archivedAt] = archivedAt
    }

    func toRecord() throws -> SessionRecord {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.invalidID(id)
        }
        guard let label = SessionColorLabel(rawValue: colorLabel) else {
            throw RepositoryError.invalidColorLabel(colorLabel)
        }
        return SessionRecord(
            id: SessionID(rawValue: uuid),
            title: title,
            workingDirectory: workingDirectory,
            createdAt: Date(timeIntervalSince1970: createdAt),
            lastActiveAt: Date(timeIntervalSince1970: lastActiveAt),
            colorLabel: label,
            isPinned: isPinned,
            orderIndex: orderIndex
        )
    }
}

// MARK: - Repository

actor SessionRepository: SessionRepositoryProtocol {
    private let db: any DatabaseServiceProtocol

    init(db: any DatabaseServiceProtocol) {
        self.db = db
    }

    func fetchAll() async throws -> [SessionRecord] {
        try await db.read { database in
            let rows = try SessionRow
                .filter(sql: "archived_at IS NULL")
                .order(sql: "is_pinned DESC, order_index ASC")
                .fetchAll(database)
            return try rows.map { try $0.toRecord() }
        }
    }

    func save(_ record: SessionRecord) async throws {
        let row = SessionRow(record: record)
        try await db.write { database in
            try row.save(database)
        }
    }

    func delete(id: SessionID) async throws {
        let idStr = id.rawValue.uuidString
        try await db.write { database in
            try database.execute(
                sql: "DELETE FROM sessions WHERE id = ?",
                arguments: [idStr]
            )
        }
    }

    func archive(id: SessionID) async throws {
        let idStr = id.rawValue.uuidString
        let now = Date().timeIntervalSince1970
        try await db.write { database in
            try database.execute(
                sql: "UPDATE sessions SET archived_at = ? WHERE id = ?",
                arguments: [now, idStr]
            )
        }
    }

    func search(query: String) async throws -> [SessionRecord] {
        guard query.count >= AppConfig.Search.minQueryLength else { return [] }
        let ftsQuery = safeFTSQuery(query)
        return try await db.read { database in
            let rows = try SessionRow.fetchAll(
                database,
                sql: """
                    SELECT s.* FROM sessions s
                    JOIN sessions_fts fts ON s.rowid = fts.rowid
                    WHERE sessions_fts MATCH ? AND s.archived_at IS NULL
                    ORDER BY rank
                    LIMIT ?
                    """,
                arguments: [ftsQuery, AppConfig.Search.maxResults]
            )
            return try rows.map { try $0.toRecord() }
        }
    }

    func reorder(ids: [SessionID]) async throws {
        let pairs = ids.enumerated().map { index, id in
            (index, id.rawValue.uuidString)
        }
        try await db.write { database in
            for (index, idStr) in pairs {
                try database.execute(
                    sql: "UPDATE sessions SET order_index = ? WHERE id = ?",
                    arguments: [index, idStr]
                )
            }
        }
    }

    func setColorLabel(id: SessionID, label: SessionColorLabel) async throws {
        let idStr = id.rawValue.uuidString
        try await db.write { database in
            try database.execute(
                sql: "UPDATE sessions SET color_label = ? WHERE id = ?",
                arguments: [label.rawValue, idStr]
            )
        }
    }

    func setPinned(id: SessionID, pinned: Bool) async throws {
        let idStr = id.rawValue.uuidString
        let pinnedInt = pinned ? 1 : 0
        try await db.write { database in
            try database.execute(
                sql: "UPDATE sessions SET is_pinned = ? WHERE id = ?",
                arguments: [pinnedInt, idStr]
            )
        }
    }

    // MARK: - Private

    private func safeFTSQuery(_ raw: String) -> String {
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\"*"
    }
}
