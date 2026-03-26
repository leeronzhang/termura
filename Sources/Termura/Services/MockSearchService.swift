import Foundation

/// Test double for `SearchServiceProtocol`.
actor MockSearchService: SearchServiceProtocol {
    var stubbedResult: SearchResults = .empty
    var searchCallCount = 0
    var lastQuery: String?

    func search(query: String) async throws -> SearchResults {
        searchCallCount += 1
        lastQuery = query
        return stubbedResult
    }
}
