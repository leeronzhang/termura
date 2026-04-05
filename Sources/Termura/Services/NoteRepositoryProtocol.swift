import Foundation

protocol NoteRepositoryProtocol: Actor {
    func fetchAll() async throws -> [NoteRecord]
    func save(_ note: NoteRecord) async throws
    func delete(id: NoteID) async throws
    func search(query: String) async throws -> [NoteRecord]

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
}
