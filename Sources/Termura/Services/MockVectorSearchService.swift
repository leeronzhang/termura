import Foundation

/// Test double for `VectorSearchServiceProtocol`.
/// Supports error simulation via `stubbedError`.
actor MockVectorSearchService: VectorSearchServiceProtocol {
    var stubbedSearchResults: [SearchHit] = []
    /// When set, `search` throws this error and `indexSession`/`indexRuleFile` become no-ops.
    var stubbedError: (any Error)?
    var indexSessionCallCount = 0
    var indexRuleFileCallCount = 0
    var searchCallCount = 0
    var clearCallCount = 0
    private(set) var indexSize: Int = 0

    func indexSession(sessionID: SessionID, chunks: [OutputChunk]) async {
        indexSessionCallCount += 1
        guard stubbedError == nil else { return }
        indexSize += chunks.count
    }

    func indexRuleFile(filePath: String, sections: [RuleSection]) async {
        indexRuleFileCallCount += 1
        guard stubbedError == nil else { return }
        indexSize += sections.count
    }

    func search(query: String, topK: Int) async -> [SearchHit] {
        searchCallCount += 1
        if stubbedError != nil { return [] }
        return Array(stubbedSearchResults.prefix(topK))
    }

    func clearIndex() {
        clearCallCount += 1
        indexSize = 0
    }
}
