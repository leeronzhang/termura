import Foundation

/// Test double for `VectorSearchServiceProtocol`.
actor MockVectorSearchService: VectorSearchServiceProtocol {
    var stubbedSearchResults: [SearchHit] = []
    var indexSessionCallCount = 0
    var indexRuleFileCallCount = 0
    var searchCallCount = 0
    var clearCallCount = 0
    private(set) var indexSize: Int = 0

    func indexSession(sessionID: SessionID, chunks: [OutputChunk]) async {
        indexSessionCallCount += 1
        indexSize += chunks.count
    }

    func indexRuleFile(filePath: String, sections: [RuleSection]) async {
        indexRuleFileCallCount += 1
        indexSize += sections.count
    }

    func search(query: String, topK: Int) async -> [SearchHit] {
        searchCallCount += 1
        return Array(stubbedSearchResults.prefix(topK))
    }

    func clearIndex() {
        clearCallCount += 1
        indexSize = 0
    }
}
