import Foundation

/// Pure value type representing a Markdown note.
/// No framework imports — pure domain model.
struct NoteRecord: Identifiable, Hashable, Sendable {
    let id: NoteID
    var title: String
    var body: String
    var isSnippet: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: NoteID = NoteID(), title: String = "", body: String = "", isSnippet: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.isSnippet = isSnippet
        createdAt = Date()
        updatedAt = Date()
    }
}
