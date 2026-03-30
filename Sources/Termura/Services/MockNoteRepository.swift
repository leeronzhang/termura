import Foundation

#if DEBUG

/// In-memory note repository for unit tests and previews. No GRDB dependency.
actor MockNoteRepository: NoteRepositoryProtocol {
    private var store: [NoteID: NoteRecord] = [:]
    private var order: [NoteID] = []

    func fetchAll() async throws -> [NoteRecord] {
        order.compactMap { store[$0] }
    }

    func save(_ note: NoteRecord) async throws {
        if store[note.id] == nil { order.append(note.id) }
        store[note.id] = note
    }

    func delete(id: NoteID) async throws {
        store[id] = nil
        order.removeAll { $0 == id }
    }

    func search(query: String) async throws -> [NoteRecord] {
        let lowered = query.lowercased()
        return order.compactMap { store[$0] }.filter {
            $0.title.lowercased().contains(lowered) ||
                $0.body.lowercased().contains(lowered)
        }
    }
}

#endif
