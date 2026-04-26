import Foundation

protocol NoteRepositoryProtocol: Actor {
    func fetchAll() async throws -> [NoteRecord]
    func save(_ note: NoteRecord) async throws
    func delete(id: NoteID) async throws
    func search(query: String) async throws -> [NoteRecord]

    // MARK: - Relationship queries (derived from note frontmatter + body)

    /// Notes whose body or frontmatter links to a target note title (wiki-link or `compiled_from`).
    /// Returned records are sorted by `updatedAt` descending. Empty if the title has no inbound links.
    func backlinks(toTitle title: String) async throws -> [NoteRecord]
    /// Notes carrying a given tag.
    func notes(taggedWith tag: String) async throws -> [NoteRecord]

    // MARK: - Lifecycle

    /// Begin monitoring the backing store for external changes (e.g. file-system watcher).
    /// Default implementation is a no-op for repositories that do not need watching.
    func startWatching() async throws
    /// Stop monitoring. Must be called symmetrically with `startWatching` on teardown.
    func stopWatching() async
}

extension NoteRepositoryProtocol {
    func startWatching() async throws {}
    func stopWatching() async {}
    func backlinks(toTitle _: String) async throws -> [NoteRecord] { [] }
    func notes(taggedWith _: String) async throws -> [NoteRecord] { [] }
}
