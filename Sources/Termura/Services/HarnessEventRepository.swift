import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "HarnessEventRepository")

// MARK: - Protocol

protocol HarnessEventRepositoryProtocol: Actor {
    func fetchEvents(for sessionID: SessionID) async throws -> [HarnessEvent]
    func save(_ event: HarnessEvent) async throws
    func fetchEvents(ofType type: HarnessEventType, for sessionID: SessionID) async throws -> [HarnessEvent]
}

// MARK: - GRDB Row Adapter

private struct HarnessEventRow: FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "harness_events"

    var id: String
    var sessionId: String
    var eventType: String
    var payload: String
    var createdAt: Double

    enum Columns: String, ColumnExpression {
        case id
        case sessionId = "session_id"
        case eventType = "event_type"
        case payload
        case createdAt = "created_at"
    }

    init(row: Row) throws {
        id = row[Columns.id]
        sessionId = row[Columns.sessionId]
        eventType = row[Columns.eventType]
        payload = row[Columns.payload]
        createdAt = row[Columns.createdAt]
    }

    init(event: HarnessEvent) {
        id = event.id.uuidString
        sessionId = event.sessionID.rawValue.uuidString
        eventType = event.eventType.rawValue
        payload = event.payload
        createdAt = event.createdAt.timeIntervalSince1970
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.sessionId] = sessionId
        container[Columns.eventType] = eventType
        container[Columns.payload] = payload
        container[Columns.createdAt] = createdAt
    }

    func toEvent() throws -> HarnessEvent {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.invalidID(rawValue: id, entity: "HarnessEvent")
        }
        guard let sessionUUID = UUID(uuidString: sessionId) else {
            throw RepositoryError.invalidID(rawValue: sessionId, entity: "HarnessEvent.session")
        }
        guard let type = HarnessEventType(rawValue: eventType) else {
            throw RepositoryError.invalidID(rawValue: eventType, entity: "HarnessEventType")
        }
        return HarnessEvent(
            id: uuid,
            sessionID: SessionID(rawValue: sessionUUID),
            eventType: type,
            payload: payload,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

// MARK: - Implementation

actor HarnessEventRepository: HarnessEventRepositoryProtocol {
    private let db: any DatabaseServiceProtocol

    init(db: any DatabaseServiceProtocol) {
        self.db = db
    }

    func fetchEvents(for sessionID: SessionID) async throws -> [HarnessEvent] {
        let idStr = sessionID.rawValue.uuidString
        return try await db.read { database in
            let rows = try HarnessEventRow.fetchAll(
                database,
                sql: """
                SELECT * FROM harness_events
                WHERE session_id = ?
                ORDER BY created_at ASC
                """,
                arguments: [idStr]
            )
            return rows.compactIsolatedMap(
                logger: logger,
                recordKind: "harness_event",
                rowID: { $0.id },
                transform: { try $0.toEvent() }
            )
        }
    }

    func save(_ event: HarnessEvent) async throws {
        let row = HarnessEventRow(event: event)
        try await db.write { database in
            try row.save(database)
        }
        logger.info("Saved harness event \(event.id) type=\(event.eventType.rawValue)")
    }

    func fetchEvents(
        ofType type: HarnessEventType,
        for sessionID: SessionID
    ) async throws -> [HarnessEvent] {
        let idStr = sessionID.rawValue.uuidString
        return try await db.read { database in
            let rows = try HarnessEventRow.fetchAll(
                database,
                sql: """
                SELECT * FROM harness_events
                WHERE session_id = ? AND event_type = ?
                ORDER BY created_at ASC
                """,
                arguments: [idStr, type.rawValue]
            )
            return rows.compactIsolatedMap(
                logger: logger,
                recordKind: "harness_event",
                rowID: { $0.id },
                transform: { try $0.toEvent() }
            )
        }
    }
}
