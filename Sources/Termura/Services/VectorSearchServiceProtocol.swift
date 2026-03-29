import Foundation

// MARK: - Result types (always compiled — referenced by protocol and DataScope)

/// A search result with relevance score.
struct SearchHit: Identifiable, Sendable {
    let id = UUID()
    let score: Float
    let text: String
    let sessionID: SessionID?
    let chunkID: UUID?
    let filePath: String?
    let sectionHeading: String?

    var isSessionResult: Bool { sessionID != nil }
    var isRuleResult: Bool { filePath != nil }
}

// MARK: - Protocol

/// Protocol abstracting semantic vector search across sessions and rule files.
/// The concrete implementation (`VectorSearchService`) is scaffolding only and is
/// excluded from release builds via `#if DEBUG`. `DataScope.vectorSearchService`
/// remains `nil` in production until a real Core ML model replaces the FNV stub.
protocol VectorSearchServiceProtocol: Actor {
    func indexSession(sessionID: SessionID, chunks: [OutputChunk]) async
    func indexRuleFile(filePath: String, sections: [RuleSection]) async
    func search(query: String, topK: Int) async -> [SearchHit]
    func clearIndex()
    var indexSize: Int { get }
}
