import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SearchService")

struct SearchResults: Sendable {
    let sessions: [SessionRecord]
    let notes: [NoteRecord]
    let query: String

    static let empty = SearchResults(sessions: [], notes: [], query: "")
}

actor SearchService {
    private let sessionRepository: any SessionRepositoryProtocol
    private let noteRepository: any NoteRepositoryProtocol

    init(
        sessionRepository: any SessionRepositoryProtocol,
        noteRepository: any NoteRepositoryProtocol
    ) {
        self.sessionRepository = sessionRepository
        self.noteRepository = noteRepository
    }

    func search(query: String) async throws -> SearchResults {
        guard query.count >= AppConfig.Search.minQueryLength else {
            return SearchResults.empty
        }
        async let sessions = sessionRepository.search(query: query)
        async let notes = noteRepository.search(query: query)
        let (foundSessions, foundNotes) = try await (sessions, notes)
        return SearchResults(sessions: foundSessions, notes: foundNotes, query: query)
    }
}
