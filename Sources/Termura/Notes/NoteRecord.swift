import Foundation

/// Pure value type representing a Markdown note.
/// No framework imports — pure domain model.
struct NoteRecord: Identifiable, Hashable, Sendable {
    let id: NoteID
    var title: String
    var body: String
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: NoteID = NoteID(), title: String = "", body: String = "", isFavorite: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.isFavorite = isFavorite
        createdAt = Date()
        updatedAt = Date()
    }

    /// Canonical sort order for notes: favorites first, then by updatedAt descending.
    /// Single source of truth — used by repository and ViewModel.
    static func displayOrder(lhs: NoteRecord, rhs: NoteRecord) -> Bool {
        if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
        return lhs.updatedAt > rhs.updatedAt
    }
}
