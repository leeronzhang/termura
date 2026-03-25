import Foundation

/// Protocol abstracting full-text search across sessions and notes.
protocol SearchServiceProtocol: Actor {
    func search(query: String) async throws -> SearchResults
}
