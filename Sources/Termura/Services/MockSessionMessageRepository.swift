import Foundation

/// Test double for `SessionMessageRepositoryProtocol`.
actor MockSessionMessageRepository: SessionMessageRepositoryProtocol {
    var savedMessages: [SessionMessage] = []

    func fetchMessages(
        for sessionID: SessionID,
        contentType: MessageContentType?
    ) async throws -> [SessionMessage] {
        savedMessages.filter { $0.sessionID == sessionID }
    }

    func save(_ message: SessionMessage) async throws {
        savedMessages.append(message)
    }

    func delete(id: SessionMessageID) async throws {
        savedMessages.removeAll { $0.id == id }
    }

    func deleteAll(for sessionID: SessionID) async throws {
        savedMessages.removeAll { $0.sessionID == sessionID }
    }

    func countTokens(
        for sessionID: SessionID,
        contentType: MessageContentType
    ) async throws -> Int {
        0
    }
}
