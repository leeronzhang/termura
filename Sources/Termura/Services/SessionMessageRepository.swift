import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionMessageRepository")

// MARK: - Protocol

protocol SessionMessageRepositoryProtocol: Actor {
    func fetchMessages(for sessionID: SessionID, contentType: MessageContentType?) async throws -> [SessionMessage]
    func save(_ message: SessionMessage) async throws
    func delete(id: SessionMessageID) async throws
    func deleteAll(for sessionID: SessionID) async throws
    func countTokens(for sessionID: SessionID, contentType: MessageContentType) async throws -> Int
}

// MARK: - GRDB Row Adapter

private struct MessageRow: FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "session_messages"

    var id: String
    var sessionId: String
    var role: String
    var contentType: String
    var content: String
    var tokenCount: Int
    var createdAt: Double

    enum Columns: String, ColumnExpression {
        case id
        case sessionId = "session_id"
        case role
        case contentType = "content_type"
        case content
        case tokenCount = "token_count"
        case createdAt = "created_at"
    }

    init(row: Row) throws {
        id = row[Columns.id]
        sessionId = row[Columns.sessionId]
        role = row[Columns.role]
        contentType = row[Columns.contentType]
        content = row[Columns.content]
        tokenCount = row[Columns.tokenCount]
        createdAt = row[Columns.createdAt]
    }

    init(message: SessionMessage) {
        id = message.id.rawValue.uuidString
        sessionId = message.sessionID.rawValue.uuidString
        role = message.role.rawValue
        contentType = message.contentType.rawValue
        content = message.content
        tokenCount = message.tokenCount
        createdAt = message.createdAt.timeIntervalSince1970
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.sessionId] = sessionId
        container[Columns.role] = role
        container[Columns.contentType] = contentType
        container[Columns.content] = content
        container[Columns.tokenCount] = tokenCount
        container[Columns.createdAt] = createdAt
    }

    func toMessage() throws -> SessionMessage {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.invalidID(rawValue: id, entity: "SessionMessage")
        }
        guard let sessionUUID = UUID(uuidString: sessionId) else {
            throw RepositoryError.invalidID(rawValue: sessionId, entity: "SessionMessage.session")
        }
        guard let msgRole = MessageRole(rawValue: role) else {
            throw RepositoryError.invalidID(rawValue: role, entity: "MessageRole")
        }
        guard let msgType = MessageContentType(rawValue: contentType) else {
            throw RepositoryError.invalidID(rawValue: contentType, entity: "MessageContentType")
        }
        return SessionMessage(
            id: SessionMessageID(rawValue: uuid),
            sessionID: SessionID(rawValue: sessionUUID),
            role: msgRole,
            contentType: msgType,
            content: content,
            tokenCount: tokenCount,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

// MARK: - Implementation

actor SessionMessageRepository: SessionMessageRepositoryProtocol {
    private let db: any DatabaseServiceProtocol

    init(db: any DatabaseServiceProtocol) {
        self.db = db
    }

    func fetchMessages(
        for sessionID: SessionID,
        contentType: MessageContentType? = nil
    ) async throws -> [SessionMessage] {
        let idStr = sessionID.rawValue.uuidString
        return try await db.read { database in
            let rows: [MessageRow] = if let ct = contentType {
                try MessageRow.fetchAll(
                    database,
                    sql: """
                    SELECT * FROM session_messages
                    WHERE session_id = ? AND content_type = ?
                    ORDER BY created_at ASC
                    """,
                    arguments: [idStr, ct.rawValue]
                )
            } else {
                try MessageRow.fetchAll(
                    database,
                    sql: """
                    SELECT * FROM session_messages
                    WHERE session_id = ?
                    ORDER BY created_at ASC
                    """,
                    arguments: [idStr]
                )
            }
            return try rows.map { try $0.toMessage() }
        }
    }

    func save(_ message: SessionMessage) async throws {
        let row = MessageRow(message: message)
        try await db.write { database in
            try row.save(database)
        }
    }

    func delete(id: SessionMessageID) async throws {
        let idStr = id.rawValue.uuidString
        try await db.write { database in
            try database.execute(
                sql: "DELETE FROM session_messages WHERE id = ?",
                arguments: [idStr]
            )
        }
    }

    func deleteAll(for sessionID: SessionID) async throws {
        let idStr = sessionID.rawValue.uuidString
        try await db.write { database in
            try database.execute(
                sql: "DELETE FROM session_messages WHERE session_id = ?",
                arguments: [idStr]
            )
        }
    }

    func countTokens(
        for sessionID: SessionID,
        contentType: MessageContentType
    ) async throws -> Int {
        let idStr = sessionID.rawValue.uuidString
        return try await db.read { database in
            let count = try Int.fetchOne(
                database,
                sql: """
                SELECT COALESCE(SUM(token_count), 0)
                FROM session_messages
                WHERE session_id = ? AND content_type = ?
                """,
                arguments: [idStr, contentType.rawValue]
            )
            return count ?? 0
        }
    }
}
