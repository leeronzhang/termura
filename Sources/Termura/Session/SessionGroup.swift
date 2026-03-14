import Foundation

/// Logical grouping of sessions for sidebar organisation.
struct SessionGroup: Identifiable, Sendable {
    let id: UUID
    var name: String
    var colorLabel: SessionColorLabel
    var sessionIDs: [SessionID]

    init(
        id: UUID = UUID(),
        name: String,
        colorLabel: SessionColorLabel = .none,
        sessionIDs: [SessionID] = []
    ) {
        self.id = id
        self.name = name
        self.colorLabel = colorLabel
        self.sessionIDs = sessionIDs
    }
}
