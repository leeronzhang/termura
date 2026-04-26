import Foundation

/// Pure value type representing a Markdown note.
/// No framework imports — pure domain model.
public struct NoteRecord: Identifiable, Hashable, Sendable {
    public let id: NoteID
    public var title: String
    public var body: String
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Tags parsed from front-matter `tags:` field. Used for categorization and P3 visualization.
    public var tags: [String]
    /// Free-form citation strings parsed from front-matter `references:` field.
    /// Each entry is rendered as one item in the bottom References section.
    /// P1: simple string array. P3 will upgrade to structured references.
    public var references: [String]
    /// True when this note is stored as a folder (`slug/README.md` + attachments)
    /// rather than a single flat Markdown file.
    public var isFolder: Bool

    public init(
        id: NoteID = NoteID(),
        title: String = "",
        body: String = "",
        isFavorite: Bool = false,
        tags: [String] = [],
        references: [String] = [],
        isFolder: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isFavorite = isFavorite
        self.tags = tags
        self.references = references
        self.isFolder = isFolder
        createdAt = Date()
        updatedAt = Date()
    }

    /// Canonical sort order for notes: favorites first, then by updatedAt descending.
    /// Single source of truth — used by repository and ViewModel.
    public static func displayOrder(lhs: NoteRecord, rhs: NoteRecord) -> Bool {
        if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
        return lhs.updatedAt > rhs.updatedAt
    }
}
