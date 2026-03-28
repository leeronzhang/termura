import Foundation
import OSLog

#if DEBUG

private let logger = Logger(subsystem: "com.termura.app", category: "VectorSearchService")

/// In-memory vector search service for semantic queries across sessions and rules.
/// Placeholder for sqlite-vec integration; uses brute-force cosine similarity.
///
/// DEBUG-ONLY: The underlying `EmbeddingService` uses FNV hash vectors that carry
/// no semantic information. Do NOT enable in production until replaced with a real
/// Core ML model. See `EmbeddingService` for upgrade path.
actor VectorSearchService: VectorSearchServiceProtocol {
    private var index: [IndexEntry] = []
    private let embeddingService: EmbeddingService

    init(embeddingService: EmbeddingService) {
        self.embeddingService = embeddingService
    }

    // MARK: - Indexing

    /// Index a session's output chunks.
    func indexSession(sessionID: SessionID, chunks: [OutputChunk]) async {
        let service = embeddingService
        for chunk in chunks {
            let text = chunk.outputLines.joined(separator: " ")
            let textChunks = await service.chunkText(text)
            for tc in textChunks {
                let vector = await service.embed(tc.text)
                let entry = IndexEntry(
                    sessionID: sessionID,
                    chunkID: chunk.id,
                    text: tc.text,
                    vector: vector
                )
                index.append(entry)
            }
        }
        logger.info("Indexed \(chunks.count) chunks for session \(sessionID)")
    }

    /// Index a rule file's sections.
    func indexRuleFile(filePath: String, sections: [RuleSection]) async {
        let service = embeddingService
        for section in sections {
            let text = "\(section.heading)\n\(section.body)"
            let vector = await service.embed(text)
            let entry = IndexEntry(
                sessionID: nil,
                chunkID: nil,
                text: text,
                vector: vector,
                filePath: filePath,
                sectionHeading: section.heading
            )
            index.append(entry)
        }
    }

    // MARK: - Search

    /// Find the top-K most similar entries to a query.
    func search(query: String, topK: Int = AppConfig.SemanticSearch.topK) async -> [SearchHit] {
        let queryVector = await embeddingService.embed(query)
        let service = embeddingService

        var scored: [(Float, IndexEntry)] = []
        for entry in index {
            let sim = await service.cosineSimilarity(queryVector, entry.vector)
            scored.append((sim, entry))
        }

        scored.sort { $0.0 > $1.0 }
        return scored.prefix(topK).map { score, entry in
            SearchHit(
                score: score,
                text: entry.text,
                sessionID: entry.sessionID,
                chunkID: entry.chunkID,
                filePath: entry.filePath,
                sectionHeading: entry.sectionHeading
            )
        }
    }

    /// Clear all indexed data.
    func clearIndex() {
        index.removeAll()
    }

    /// Number of indexed entries.
    var indexSize: Int { index.count }
}

// MARK: - Supporting Types

private struct IndexEntry: Sendable {
    let sessionID: SessionID?
    let chunkID: UUID?
    let text: String
    let vector: [Float]
    var filePath: String?
    var sectionHeading: String?
}

#endif
