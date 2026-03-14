import Foundation

/// Immutable value type representing a terminal session.
/// No framework imports — pure domain model.
struct SessionRecord: Identifiable, Hashable, Sendable {
    let id: SessionID
    var title: String
    var workingDirectory: String
    var createdAt: Date
    var lastActiveAt: Date
    var colorLabel: SessionColorLabel
    var isPinned: Bool
    var orderIndex: Int

    init(
        id: SessionID = SessionID(),
        title: String = "Terminal",
        workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        colorLabel: SessionColorLabel = .none,
        isPinned: Bool = false,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.colorLabel = colorLabel
        self.isPinned = isPinned
        self.orderIndex = orderIndex
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
