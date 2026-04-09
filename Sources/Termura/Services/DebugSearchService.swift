import Foundation

#if DEBUG

/// Debug fallback for previews and local environment defaults.
actor DebugSearchService: SearchServiceProtocol {
    var stubbedResult: SearchResults = .empty

    func search(query: String) async throws -> SearchResults {
        stubbedResult
    }
}

#endif
