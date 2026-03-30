import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionRepository")

// MARK: - Session Tree

extension SessionRepository {
    func fetchChildren(of parentID: SessionID) async throws -> [SessionRecord] {
        let idStr = parentID.rawValue.uuidString
        return try await db.read { database in
            let rows = try SessionRow.fetchAll(
                database,
                sql: """
                SELECT * FROM sessions
                WHERE parent_id = ? AND archived_at IS NULL
                ORDER BY created_at ASC
                """,
                arguments: [idStr]
            )
            return try rows.map { try $0.toRecord() }
        }
    }

    func fetchAncestors(of sessionID: SessionID) async throws -> [SessionRecord] {
        let idStr = sessionID.rawValue.uuidString
        return try await db.read { database in
            let rows = try SessionRow.fetchAll(
                database,
                sql: """
                WITH RECURSIVE ancestors(id) AS (
                    SELECT parent_id FROM sessions WHERE id = ?
                    UNION ALL
                    SELECT s.parent_id FROM sessions s
                    JOIN ancestors a ON s.id = a.id
                    WHERE s.parent_id IS NOT NULL
                )
                SELECT s.* FROM sessions s
                JOIN ancestors a ON s.id = a.id
                ORDER BY s.created_at ASC
                """,
                arguments: [idStr]
            )
            return try rows.map { try $0.toRecord() }
        }
    }

    func createBranch(
        from parentID: SessionID,
        type: BranchType,
        title: String
    ) async throws -> SessionRecord {
        let ancestors = try await fetchAncestors(of: parentID)
        guard ancestors.count < AppConfig.SessionTree.maxDepth else {
            throw RepositoryError.branchDepthExceeded(currentDepth: ancestors.count)
        }
        let record = SessionRecord(
            title: title,
            parentID: parentID,
            branchType: type
        )
        try await save(record)
        logger.info("Created branch \(record.id) from \(parentID) type=\(type.rawValue)")
        return record
    }

    func updateSummary(_ sessionID: SessionID, summary: String) async throws {
        let idStr = sessionID.rawValue.uuidString
        let trimmed = String(summary.prefix(AppConfig.SessionTree.summaryMaxLength))
        try await db.write { database in
            try database.execute(
                sql: "UPDATE sessions SET summary = ? WHERE id = ?",
                arguments: [trimmed, idStr]
            )
        }
    }
}
