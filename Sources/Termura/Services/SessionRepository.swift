import Foundation
import GRDB
import OSLog

// MARK: - GRDB Row Adapter (private to this file)

// SessionRow is internal (not private) so SessionRepository+Tree.swift can access it.
struct SessionRow: FetchableRecord, PersistableRecord, Sendable {
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
    var parentId: String?
    var summary: String
    var branchType: String
    var agentType: String
    var endedAt: Double?

    enum Columns: String, ColumnExpression {
        case id, title
        case workingDirectory = "working_directory"
        case createdAt = "created_at"
        case lastActiveAt = "last_active_at"
        case colorLabel = "color_label"
        case isPinned = "is_pinned"
        case orderIndex = "order_index"
        case archivedAt = "archived_at"
        case parentId = "parent_id"
        case summary
        case branchType = "branch_type"
        case agentType = "agent_type"
        case endedAt = "ended_at"
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
        parentId = row[Columns.parentId]
        // These columns were added via ALTER TABLE (v5, v7 migrations) without NOT NULL,
        // so rows from earlier schema versions may contain NULL. Defaults are intentional.
        summary = row[Columns.summary] ?? ""
        branchType = row[Columns.branchType] ?? BranchType.main.rawValue
        agentType = row[Columns.agentType] ?? AgentType.unknown.rawValue
        // v9: ended_at is nullable; NULL means active.
        endedAt = row[Columns.endedAt]
    }

    init(record: SessionRecord, archivedAt: Date? = nil) {
        id = record.id.rawValue.uuidString
        title = record.title
        workingDirectory = record.workingDirectory ?? ""
        createdAt = record.createdAt.timeIntervalSince1970
        lastActiveAt = record.lastActiveAt.timeIntervalSince1970
        colorLabel = record.colorLabel.rawValue
        isPinned = record.isPinned
        orderIndex = record.orderIndex
        self.archivedAt = archivedAt?.timeIntervalSince1970
        parentId = record.parentID?.rawValue.uuidString
        summary = record.summary ?? ""
        branchType = record.branchType.rawValue
        agentType = record.agentType.rawValue
        endedAt = record.endedAt?.timeIntervalSince1970
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
        container[Columns.parentId] = parentId
        container[Columns.summary] = summary
        container[Columns.branchType] = branchType
        container[Columns.agentType] = agentType
        container[Columns.endedAt] = endedAt
    }

    func toRecord() throws -> SessionRecord {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.invalidID(rawValue: id, entity: "Session")
        }
        guard let label = SessionColorLabel(rawValue: colorLabel) else {
            throw RepositoryError.invalidColorLabel(rawValue: colorLabel)
        }
        guard let branch = BranchType(rawValue: branchType) else {
            throw RepositoryError.invalidBranchType(rawValue: branchType)
        }
        // AgentType has a dedicated .unknown case for forward-compatible schema evolution;
        // unrecognised agent strings degrade gracefully rather than making the session
        // unloadable. SessionColorLabel/BranchType have no such fallback — hence they throw.
        let agent = AgentType(rawValue: agentType) ?? .unknown
        let parentSessionID: SessionID? = parentId.flatMap { str in
            UUID(uuidString: str).map { SessionID(rawValue: $0) }
        }
        return SessionRecord(
            id: SessionID(rawValue: uuid),
            title: title,
            workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory,
            createdAt: Date(timeIntervalSince1970: createdAt),
            lastActiveAt: Date(timeIntervalSince1970: lastActiveAt),
            colorLabel: label,
            isPinned: isPinned,
            orderIndex: orderIndex,
            parentID: parentSessionID,
            summary: summary.isEmpty ? nil : summary,
            branchType: branch,
            agentType: agent,
            endedAt: endedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

// MARK: - Repository

actor SessionRepository: SessionRepositoryProtocol {
    // internal: SessionRepository+Tree.swift needs access for tree queries.
    let db: any DatabaseServiceProtocol
    private let clock: any AppClock

    init(db: any DatabaseServiceProtocol, clock: any AppClock = LiveClock()) {
        self.db = db
        self.clock = clock
    }

    func fetchAll() async throws -> [SessionRecord] {
        try await db.read { database in
            let rows = try SessionRow
                .filter(sql: "archived_at IS NULL")
                .order(sql: "is_pinned DESC, order_index ASC")
                .fetchAll(database)
            // Title sanitization: strips agent icon prefixes persisted by older app versions
            // before the prefix list was expanded. Applied here so every caller receives
            // canonical records without needing a post-fetch loop.
            // TitleSanitizer (Session/) is a pure-function utility — calling it from the
            // repository layer is a deliberate pragmatic exception to the usual dependency
            // direction rule; no domain side-effects are involved.
            return try rows.map { row in
                var record = try row.toRecord()
                record.title = TitleSanitizer.stripAgentPrefixes(record.title)
                return record
            }
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
        let now = clock.now().timeIntervalSince1970
        try await db.write { database in
            try database.execute(
                sql: "UPDATE sessions SET archived_at = ? WHERE id = ?",
                arguments: [now, idStr]
            )
        }
    }

    func search(query: String) async throws -> [SessionRecord] {
        guard query.count >= AppConfig.Search.minQueryLength else { return [] }
        let ftsQuery = FTS5.escapeQuery(query)
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
        guard !ids.isEmpty else { return }
        // Enumerate upfront so each ID carries its final order_index across all batches.
        let pairs = ids.enumerated().map { (index: $0, idStr: $1.rawValue.uuidString) }
        let batchSize = AppConfig.Persistence.reorderBatchSize
        // Single write transaction: all batches commit together or roll back together.
        try await db.write { database in
            for batchStart in stride(from: 0, to: pairs.count, by: batchSize) {
                let batch = Array(pairs[batchStart ..< min(batchStart + batchSize, pairs.count)])
                // Dynamic SQL: safe. Interpolated fragments contain only static SQL
                // skeleton ("WHEN id = ? THEN ?" / "?") — no user data. All actual
                // values are passed separately via StatementArguments (parameterized
                // binding). 3 bindings per row: 2 in CASE WHEN + 1 in IN clause
                // (total <= 999 per batch, enforced by reorderBatchSize).
                let cases = batch.map { _ in "WHEN id = ? THEN ?" }.joined(separator: " ")
                let holders = batch.map { _ in "?" }.joined(separator: ", ")
                var vals: [DatabaseValue] = []
                for pair in batch { vals.append(pair.idStr.databaseValue); vals.append(pair.index.databaseValue) }
                for pair in batch { vals.append(pair.idStr.databaseValue) }
                let sql = "UPDATE sessions SET order_index = CASE \(cases) END WHERE id IN (\(holders))"
                try database.execute(sql: sql, arguments: StatementArguments(vals))
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

    func markEnded(id: SessionID, at date: Date) async throws {
        let idStr = id.rawValue.uuidString
        let timestamp = date.timeIntervalSince1970
        try await db.write { database in
            try database.execute(
                sql: "UPDATE sessions SET ended_at = ? WHERE id = ?",
                arguments: [timestamp, idStr]
            )
        }
    }

    func markReopened(id: SessionID) async throws {
        let idStr = id.rawValue.uuidString
        try await db.write { database in
            try database.execute(
                sql: "UPDATE sessions SET ended_at = NULL WHERE id = ?",
                arguments: [idStr]
            )
        }
    }

}
