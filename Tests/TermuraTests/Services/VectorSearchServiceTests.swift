import Testing
@testable import Termura

@Suite("VectorSearchService")
struct VectorSearchServiceTests {
    private func makeServices() -> (EmbeddingService, VectorSearchService) {
        let embed = EmbeddingService()
        let search = VectorSearchService(embeddingService: embed)
        return (embed, search)
    }

    private func makeChunk(
        sessionID: SessionID = SessionID(),
        command: String = "echo test",
        output: [String] = ["test output"]
    ) -> OutputChunk {
        OutputChunk(
            sessionID: sessionID,
            commandText: command,
            outputLines: output,
            rawANSI: output.joined(separator: "\n"),
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )
    }

    private func makeSection(
        heading: String = "## Test",
        body: String = "Test body content"
    ) -> RuleSection {
        RuleSection(heading: heading, level: 2, body: body, lineRange: 1 ... 5)
    }

    // MARK: - Indexing

    @Test("Index session increases index size")
    func indexSessionIncreasesSize() async {
        let (_, search) = makeServices()
        let sid = SessionID()
        let chunks = [makeChunk(sessionID: sid)]
        await search.indexSession(sessionID: sid, chunks: chunks)
        let size = await search.indexSize
        #expect(size > 0)
    }

    @Test("Index rule file sections")
    func indexRuleFileSections() async {
        let (_, search) = makeServices()
        let sections = [makeSection(heading: "## A"), makeSection(heading: "## B")]
        await search.indexRuleFile(filePath: "/test/CLAUDE.md", sections: sections)
        let size = await search.indexSize
        #expect(size >= 2)
    }

    @Test("Clear index resets to zero")
    func clearIndex() async {
        let (_, search) = makeServices()
        await search.indexSession(sessionID: SessionID(), chunks: [makeChunk()])
        await search.clearIndex()
        let size = await search.indexSize
        #expect(size == 0)
    }

    // MARK: - Search

    @Test("Search returns results sorted by score descending")
    func searchSortedByScore() async {
        let (_, search) = makeServices()
        let sid = SessionID()
        let chunks = [
            makeChunk(sessionID: sid, output: ["swift programming language"]),
            makeChunk(sessionID: sid, output: ["python data science"]),
            makeChunk(sessionID: sid, output: ["swift compiler optimization"])
        ]
        await search.indexSession(sessionID: sid, chunks: chunks)
        let hits = await search.search(query: "swift programming", topK: 10)

        guard hits.count >= 2 else {
            Issue.record("Expected at least 2 hits, got \(hits.count)")
            return
        }
        // Scores should be in descending order.
        for i in 0 ..< hits.count - 1 {
            #expect(hits[i].score >= hits[i + 1].score)
        }
    }

    @Test("Search respects topK limit")
    func searchTopK() async {
        let (_, search) = makeServices()
        let sid = SessionID()
        let chunks = (0 ..< 30).map { i in
            makeChunk(sessionID: sid, output: ["entry number \(i)"])
        }
        await search.indexSession(sessionID: sid, chunks: chunks)
        let hits = await search.search(query: "entry", topK: 5)
        #expect(hits.count <= 5)
    }

    @Test("Search on empty index returns empty")
    func searchEmptyIndex() async {
        let (_, search) = makeServices()
        let hits = await search.search(query: "anything")
        #expect(hits.isEmpty)
    }

    @Test("Session search hit has sessionID and chunkID")
    func sessionSearchHitFields() async {
        let (_, search) = makeServices()
        let sid = SessionID()
        await search.indexSession(sessionID: sid, chunks: [makeChunk(sessionID: sid)])
        let hits = await search.search(query: "test output")
        guard let hit = hits.first else {
            Issue.record("Expected at least one hit")
            return
        }
        #expect(hit.sessionID != nil)
        #expect(hit.chunkID != nil)
        #expect(hit.isSessionResult == true)
    }

    @Test("Rule search hit has filePath and sectionHeading")
    func ruleSearchHitFields() async {
        let (_, search) = makeServices()
        await search.indexRuleFile(
            filePath: "/project/CLAUDE.md",
            sections: [makeSection(heading: "## Error Handling")]
        )
        let hits = await search.search(query: "error handling")
        guard let hit = hits.first else {
            Issue.record("Expected at least one hit")
            return
        }
        #expect(hit.filePath == "/project/CLAUDE.md")
        #expect(hit.sectionHeading == "## Error Handling")
        #expect(hit.isRuleResult == true)
    }

    // MARK: - Cosine similarity

    @Test("Same text embedding has similarity ≈ 1.0")
    func sameTextSimilarity() async {
        let (embed, _) = makeServices()
        let vector = await embed.embed("hello world test")
        let sim = await embed.cosineSimilarity(vector, vector)
        #expect(sim > 0.99)
    }

    @Test("Unrelated texts have lower similarity")
    func unrelatedTextsSimilarity() async {
        let (embed, _) = makeServices()
        let vecA = await embed.embed("swift programming compiler")
        let vecB = await embed.embed("cooking recipe ingredients")
        let sim = await embed.cosineSimilarity(vecA, vecB)
        #expect(sim < 0.5)
    }
}
