import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SearchService")

struct SearchResults: Sendable {
    let sessions: [SessionRecord]
    let notes: [NoteRecord]
    let query: String

    static let empty = SearchResults(sessions: [], notes: [], query: "")
}

actor SearchService: SearchServiceProtocol {
    private let sessionRepository: any SessionRepositoryProtocol
    private let noteRepository: any NoteRepositoryProtocol
    private let metrics: (any MetricsCollectorProtocol)?

    init(
        sessionRepository: any SessionRepositoryProtocol,
        noteRepository: any NoteRepositoryProtocol,
        metrics: (any MetricsCollectorProtocol)? = nil // Optional: observability, nil = no-op
    ) {
        self.sessionRepository = sessionRepository
        self.noteRepository = noteRepository
        self.metrics = metrics
    }

    func search(query: String) async throws -> SearchResults {
        guard query.count >= AppConfig.Search.minQueryLength else {
            return SearchResults.empty
        }
        let start = ContinuousClock.now
        async let sessions = sessionRepository.search(query: query)
        async let notes = noteRepository.search(query: query)
        let (foundSessions, foundNotes) = try await (sessions, notes)
        let elapsed = ContinuousClock.now - start
        await metrics?.recordOperation(.searchQuery, duration: .searchDuration, seconds: elapsed.totalSeconds)
        return SearchResults(sessions: foundSessions, notes: foundNotes, query: query)
    }
}
