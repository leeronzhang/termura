import Foundation

protocol SessionSnapshotRepositoryProtocol: Actor {
    func save(lines: [String], for sessionID: SessionID) async throws
    func load(for sessionID: SessionID) async throws -> [String]?
    func delete(for sessionID: SessionID) async throws
}
