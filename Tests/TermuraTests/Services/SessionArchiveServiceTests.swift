import Foundation
import Testing
@testable import Termura

@Suite("SessionArchiveService")
struct SessionArchiveServiceTests {
    // MARK: - Archive

    @Test("Archive delegates to repository")
    func archiveDelegates() async throws {
        let repo = MockSessionRepository()
        let service = SessionArchiveService(repository: repo)
        let session = SessionRecord(title: "To Archive")
        try await repo.save(session)

        try await service.archive(id: session.id)

        let all = try await repo.fetchAll()
        // MockSessionRepository.archive marks the session as archived,
        // so fetchAll (which filters out archived) should be empty.
        #expect(all.isEmpty)
    }

    // MARK: - Fetch archived (stub)

    @Test("fetchArchived returns empty (Phase 3 stub)")
    func fetchArchivedReturnsEmpty() async throws {
        let repo = MockSessionRepository()
        let service = SessionArchiveService(repository: repo)
        let result = try await service.fetchArchived()
        #expect(result.isEmpty)
    }
}
