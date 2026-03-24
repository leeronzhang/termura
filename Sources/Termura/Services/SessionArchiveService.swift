import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionArchiveService")

actor SessionArchiveService {
    private let repository: any SessionRepositoryProtocol

    init(repository: any SessionRepositoryProtocol) {
        self.repository = repository
    }

    func archive(id: SessionID) async throws {
        try await repository.archive(id: id)
        logger.info("Archived session \(id)")
    }

    /// Returns archived sessions.
    /// Phase 3: returns empty — archive browser is Phase 4.
    func fetchArchived() async throws -> [SessionRecord] {
        []
    }
}
