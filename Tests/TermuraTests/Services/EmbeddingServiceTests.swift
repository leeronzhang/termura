import Foundation
import Testing
@testable import Termura

@Suite("EmbeddingService")
struct EmbeddingServiceTests {

    private func makeService() -> EmbeddingService {
        EmbeddingService()
    }

    @Test("Produces vector of correct dimension")
    func vectorDimension() async {
        let service = makeService()
        let vector = await service.embed("hello world")
        #expect(vector.count == AppConfig.SemanticSearch.embeddingDimension)
    }

    @Test("Normalized vector has unit length")
    func normalized() async {
        let service = makeService()
        let vector = await service.embed("test embedding normalization")
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        #expect(abs(norm - 1.0) < 0.01)
    }

    @Test("Same text produces same vector")
    func deterministic() async {
        let service = makeService()
        let v1 = await service.embed("deterministic test")
        let v2 = await service.embed("deterministic test")
        #expect(v1 == v2)
    }

    @Test("Different texts produce different vectors")
    func different() async {
        let service = makeService()
        let v1 = await service.embed("swift programming")
        let v2 = await service.embed("python data science")
        #expect(v1 != v2)
    }

    @Test("Cosine similarity of identical vectors is 1.0")
    func selfSimilarity() async {
        let service = makeService()
        let v = await service.embed("test")
        let sim = await service.cosineSimilarity(v, v)
        #expect(abs(sim - 1.0) < 0.001)
    }

    @Test("Chunks text into overlapping windows")
    func chunkText() async {
        let service = makeService()
        let words = (0..<500).map { "word\($0)" }.joined(separator: " ")
        let chunks = await service.chunkText(words)
        #expect(chunks.count > 1)
        #expect(chunks[0].offset == 0)
    }
}
