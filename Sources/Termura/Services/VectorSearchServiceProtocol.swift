import Foundation

/// Protocol abstracting semantic vector search across sessions and rule files.
protocol VectorSearchServiceProtocol: Actor {
    func indexSession(sessionID: SessionID, chunks: [OutputChunk]) async
    func indexRuleFile(filePath: String, sections: [RuleSection]) async
    func search(query: String, topK: Int) async -> [SearchHit]
    func clearIndex()
    var indexSize: Int { get }
}

extension VectorSearchServiceProtocol {
    /// Convenience: search with default topK from AppConfig.
    func search(query: String) async -> [SearchHit] {
        await search(query: query, topK: AppConfig.SemanticSearch.topK)
    }
}
