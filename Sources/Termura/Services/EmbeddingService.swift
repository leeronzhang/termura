import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "EmbeddingService")

/// Local embedding service for semantic search.
/// Uses a lightweight heuristic (TF-IDF-style) as a placeholder;
/// can be replaced with Core ML + MiniLM-L6 when the model is bundled.
actor EmbeddingService {
    private let dimension = AppConfig.SemanticSearch.embeddingDimension

    /// Generate an embedding vector for a text chunk.
    /// Placeholder: produces a deterministic hash-based vector.
    /// Replace with Core ML inference for production.
    func embed(_ text: String) -> [Float] {
        let tokens = tokenize(text)
        var vector = [Float](repeating: 0, count: dimension)

        for token in tokens {
            let hash = fnvHash(token)
            let idx = Int(hash % UInt64(dimension))
            vector[idx] += 1.0
        }

        // L2 normalize
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            for i in vector.indices {
                vector[i] /= norm
            }
        }

        return vector
    }

    /// Compute cosine similarity between two vectors.
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    /// Split text into overlapping chunks for indexing.
    func chunkText(_ text: String) -> [TextChunk] {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let maxTokens = AppConfig.SemanticSearch.chunkMaxTokens
        let overlap = AppConfig.SemanticSearch.chunkOverlapTokens
        var chunks: [TextChunk] = []
        var start = 0

        while start < words.count {
            let end = min(start + maxTokens, words.count)
            let slice = words[start ..< end].joined(separator: " ")
            chunks.append(TextChunk(text: slice, offset: start))
            start += maxTokens - overlap
            if start >= words.count { break }
        }

        return chunks
    }

    // MARK: - Private

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    private func fnvHash(_ string: String) -> UInt64 {
        var hashValue: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hashValue ^= UInt64(byte)
            hashValue &*= 1_099_511_628_211
        }
        return hashValue
    }
}

/// A text chunk for embedding and indexing.
struct TextChunk: Sendable {
    let text: String
    let offset: Int
}
