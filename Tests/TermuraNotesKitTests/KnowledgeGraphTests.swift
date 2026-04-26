import Foundation
@testable import TermuraNotesKit
import Testing

@Suite("KnowledgeGraphData")
struct KnowledgeGraphTests {
    // MARK: - Helpers

    private func makeNote(title: String, body: String = "", tags: [String] = []) -> NoteRecord {
        NoteRecord(title: title, body: body, tags: tags)
    }

    // MARK: - Tests

    @Test("happy path: notes + tags + backlinks produce correct graph")
    func happyPath() {
        let noteA = makeNote(title: "Auth Bug", body: "See [[Unix Tips]] for details", tags: ["auth", "bug"])
        let noteB = makeNote(title: "Unix Tips", body: "Some unix tips", tags: ["unix"])
        let noteC = makeNote(title: "Refactoring", body: "Also see [[Auth Bug]]", tags: ["auth"])

        var index = BacklinkIndex()
        index.rebuild(from: [noteA, noteB, noteC])

        let graph = KnowledgeGraphData.build(from: [noteA, noteB, noteC], backlinkIndex: index)

        // 3 note nodes + 3 tag nodes (auth, bug, unix)
        let noteNodes = graph.nodes.filter { $0.type == .note }
        let tagNodes = graph.nodes.filter { $0.type == .tag }
        #expect(noteNodes.count == 3)
        #expect(tagNodes.count == 3)

        // Tag links: noteA→auth, noteA→bug, noteB→unix, noteC→auth = 4
        let tagLinks = graph.links.filter { $0.type == .tag }
        #expect(tagLinks.count == 4)

        // Backlinks: noteA→[[Unix Tips]] and noteC→[[Auth Bug]]
        // These produce 2 undirected edges.
        let backlinkLinks = graph.links.filter { $0.type == .backlink }
        #expect(backlinkLinks.count == 2)
    }

    @Test("empty notes produce empty graph")
    func emptyNotes() {
        let index = BacklinkIndex()
        let graph = KnowledgeGraphData.build(from: [], backlinkIndex: index)
        #expect(graph.nodes.isEmpty)
        #expect(graph.links.isEmpty)
    }

    @Test("notes without tags or backlinks produce isolated note nodes")
    func noTagsNoBacklinks() {
        let noteA = makeNote(title: "Lonely Note")
        let noteB = makeNote(title: "Another Lonely")

        let index = BacklinkIndex()
        let graph = KnowledgeGraphData.build(from: [noteA, noteB], backlinkIndex: index)

        #expect(graph.nodes.count == 2)
        #expect(graph.nodes.allSatisfy { $0.type == .note })
        #expect(graph.links.isEmpty)
    }

    @Test("duplicate backlinks between same pair are deduplicated")
    func deduplicatedBacklinks() {
        // noteA links to noteB, and noteB links to noteA — should produce 1 undirected edge.
        let noteA = makeNote(title: "A", body: "See [[B]]")
        let noteB = makeNote(title: "B", body: "See [[A]]")

        var index = BacklinkIndex()
        index.rebuild(from: [noteA, noteB])

        let graph = KnowledgeGraphData.build(from: [noteA, noteB], backlinkIndex: index)
        let backlinkLinks = graph.links.filter { $0.type == .backlink }
        #expect(backlinkLinks.count == 1)
    }

    @Test("graph data is JSON encodable")
    func jSONEncodable() throws {
        let note = makeNote(title: "Test", tags: ["swift"])
        let index = BacklinkIndex()
        let graph = KnowledgeGraphData.build(from: [note], backlinkIndex: index)

        let data = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(KnowledgeGraphData.self, from: data)
        #expect(decoded.nodes.count == graph.nodes.count)
        #expect(decoded.links.count == graph.links.count)
    }
}
