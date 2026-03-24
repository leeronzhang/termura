import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "RuleFileRepository")

// MARK: - Protocol

protocol RuleFileRepositoryProtocol: Actor {
    func save(_ record: RuleFileRecord) async throws
    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord]
    func fetchLatest(for filePath: String) async throws -> RuleFileRecord?
    func fetchAll() async throws -> [RuleFileRecord]
}

// MARK: - Row Adapter

private struct RuleFileRow: FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "rule_files"

    var id: String
    var filePath: String
    var content: String
    var contentHash: String
    var sessionId: String?
    var version: Int
    var createdAt: Double

    enum Columns: String, ColumnExpression {
        case id
        case filePath = "file_path"
        case content
        case contentHash = "content_hash"
        case sessionId = "session_id"
        case version
        case createdAt = "created_at"
    }

    init(row: Row) throws {
        id = row[Columns.id]
        filePath = row[Columns.filePath]
        content = row[Columns.content]
        contentHash = row[Columns.contentHash]
        sessionId = row[Columns.sessionId]
        version = row[Columns.version]
        createdAt = row[Columns.createdAt]
    }

    init(record: RuleFileRecord) {
        id = record.id.uuidString
        filePath = record.filePath
        content = record.content
        contentHash = record.contentHash
        sessionId = record.sessionID?.rawValue.uuidString
        version = record.version
        createdAt = record.createdAt.timeIntervalSince1970
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.filePath] = filePath
        container[Columns.content] = content
        container[Columns.contentHash] = contentHash
        container[Columns.sessionId] = sessionId
        container[Columns.version] = version
        container[Columns.createdAt] = createdAt
    }

    func toRecord() throws -> RuleFileRecord {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.invalidID(id)
        }
        let sid = sessionId.flatMap { UUID(uuidString: $0) }.map { SessionID(rawValue: $0) }
        return RuleFileRecord(
            id: uuid, filePath: filePath, content: content,
            contentHash: contentHash, sessionID: sid,
            version: version,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

// MARK: - Implementation

actor RuleFileRepository: RuleFileRepositoryProtocol {
    private let db: any DatabaseServiceProtocol

    init(db: any DatabaseServiceProtocol) {
        self.db = db
    }

    func save(_ record: RuleFileRecord) async throws {
        let row = RuleFileRow(record: record)
        try await db.write { database in
            try row.save(database)
        }
        logger.info("Saved rule file version \(record.version) for \(record.fileName)")
    }

    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord] {
        try await db.read { database in
            let rows = try RuleFileRow.fetchAll(
                database,
                sql: """
                SELECT * FROM rule_files
                WHERE file_path = ?
                ORDER BY version DESC
                LIMIT ?
                """,
                arguments: [filePath, AppConfig.Harness.maxVersionHistory]
            )
            return try rows.map { try $0.toRecord() }
        }
    }

    func fetchLatest(for filePath: String) async throws -> RuleFileRecord? {
        try await db.read { database in
            let row = try RuleFileRow.fetchOne(
                database,
                sql: """
                SELECT * FROM rule_files
                WHERE file_path = ?
                ORDER BY version DESC LIMIT 1
                """,
                arguments: [filePath]
            )
            return try row?.toRecord()
        }
    }

    func fetchAll() async throws -> [RuleFileRecord] {
        try await db.read { database in
            let rows = try RuleFileRow.fetchAll(
                database,
                sql: """
                SELECT r1.* FROM rule_files r1
                INNER JOIN (
                    SELECT file_path, MAX(version) as max_ver
                    FROM rule_files GROUP BY file_path
                ) r2 ON r1.file_path = r2.file_path AND r1.version = r2.max_ver
                ORDER BY r1.file_path
                """
            )
            return try rows.map { try $0.toRecord() }
        }
    }
}
