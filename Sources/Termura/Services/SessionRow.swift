import Foundation
import GRDB

// MARK: - GRDB Row Adapter

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
        // AgentType 有 .unknown 专用降级 case，降级不影响业务正确性。
        let agent = AgentType(rawValue: agentType) ?? .unknown // AgentType .unknown 降级
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
            status: endedAt.map { .ended(at: Date(timeIntervalSince1970: $0)) } ?? .active
        )
    }
}
