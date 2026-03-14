import Foundation

protocol SessionRepositoryProtocol: Actor {
    func fetchAll() async throws -> [SessionRecord]
    func save(_ record: SessionRecord) async throws
    func delete(id: SessionID) async throws
    func archive(id: SessionID) async throws
    func search(query: String) async throws -> [SessionRecord]
    func reorder(ids: [SessionID]) async throws
    func setColorLabel(id: SessionID, label: SessionColorLabel) async throws
    func setPinned(id: SessionID, pinned: Bool) async throws
}
