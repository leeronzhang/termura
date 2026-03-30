import Foundation

/// Immutable value type representing a terminal session.
/// Supports tree structure via `parentID` — nil means root node.
/// No framework imports — pure domain model.
struct SessionRecord: Identifiable, Hashable, Sendable {
    let id: SessionID
    var title: String
    var workingDirectory: String?
    var createdAt: Date
    var lastActiveAt: Date
    var colorLabel: SessionColorLabel
    var isPinned: Bool
    var orderIndex: Int
    /// Parent session ID — nil for root sessions (no branch parent).
    var parentID: SessionID?
    /// AI-generated summary of a completed branch, inserted into parent context.
    var summary: String?
    /// Purpose categorization for branches.
    var branchType: BranchType
    /// Detected AI agent type running in this session (persisted for sidebar icon).
    var agentType: AgentType
    /// When set, the session PTY has been terminated but the record is preserved.
    /// nil = active; non-nil = ended (can be reopened).
    var endedAt: Date?

    /// True when the PTY has been terminated and the session is awaiting reopen or deletion.
    var isEnded: Bool { endedAt != nil }

    init(
        id: SessionID = SessionID(),
        title: String = "Terminal",
        workingDirectory: String? = nil,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        colorLabel: SessionColorLabel = .none,
        isPinned: Bool = false,
        orderIndex: Int = 0,
        parentID: SessionID? = nil,
        summary: String? = nil,
        branchType: BranchType = .main,
        agentType: AgentType = .unknown,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.colorLabel = colorLabel
        self.isPinned = isPinned
        self.orderIndex = orderIndex
        self.parentID = parentID
        self.summary = summary
        self.branchType = branchType
        self.agentType = agentType
        self.endedAt = endedAt
    }
}

enum SessionColorLabel: String, Sendable, Codable, CaseIterable {
    case none
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
}
