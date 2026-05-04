import Foundation
import GRDB
import OSLog

// MARK: - Repository

actor SessionRepository: SessionRepositoryProtocol {
    // internal: SessionRepository+Tree.swift needs access for tree queries.
    let db: any DatabaseServiceProtocol
    private let clock: any AppClock

    /// Static so the per-row isolation helper can capture it inside the
    /// `db.read { ... }` Sendable closure without trying to retain the
    /// actor itself.
    static let fetchLogger = Logger(subsystem: "com.termura.app", category: "SessionRepository")

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
            return rows.compactIsolatedMap(
                logger: SessionRepository.fetchLogger,
                recordKind: "session",
                rowID: { $0.id },
                transform: { row in
                    var record = try row.toRecord()
                    record.title = TitleSanitizer.stripAgentPrefixes(record.title)
                    return record
                }
            )
        }
    }

    func fetch(id: SessionID) async throws -> SessionRecord? {
        let idStr = id.rawValue.uuidString
        return try await db.read { database in
            let row = try SessionRow.fetchOne(database, key: idStr)
            return try row?.toRecord()
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
            return rows.compactIsolatedMap(
                logger: SessionRepository.fetchLogger,
                recordKind: "session",
                rowID: { $0.id },
                transform: { try $0.toRecord() }
            )
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
                for pair in batch {
                    vals.append(pair.idStr.databaseValue); vals.append(pair.index.databaseValue)
                }
                for pair in batch {
                    vals.append(pair.idStr.databaseValue)
                }
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
