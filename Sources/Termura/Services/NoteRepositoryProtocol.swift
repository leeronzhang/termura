import Foundation

protocol NoteRepositoryProtocol: Actor {
    func fetchAll() async throws -> [NoteRecord]
    func fetchSnippets() async throws -> [NoteRecord]
    func save(_ note: NoteRecord) async throws
    func delete(id: NoteID) async throws
    func search(query: String) async throws -> [NoteRecord]
    func searchSnippets(query: String) async throws -> [NoteRecord]
}
