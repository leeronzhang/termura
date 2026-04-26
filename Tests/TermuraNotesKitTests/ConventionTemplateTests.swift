import Foundation
@testable import TermuraNotesKit
import Testing

@Suite("ConventionTemplate")
struct ConventionTemplateTests {
    @Test("convention content contains key sections")
    func testConventionContent() {
        let content = ConventionTemplate.conventionContent
        #expect(content.contains("Knowledge Sinking Convention"))
        #expect(content.contains("何时沉淀"))
        #expect(content.contains("何时不沉淀"))
        #expect(content.contains("Tag 命名规范"))
        #expect(content.contains("Frontmatter 要求"))
        #expect(content.contains("CLI 命令参考"))
        #expect(content.contains("MCP 工具参考"))
        #expect(content.contains("tn create"))
    }

    @Test("claude reference snippet references CONVENTION.md")
    func claudeSnippet() {
        let snippet = ConventionTemplate.claudeReferenceSnippet
        #expect(snippet.contains("CONVENTION.md"))
        #expect(snippet.contains(ConventionTemplate.claudeMarker))
    }

    @Test("tags round-trip through NoteRecord and frontmatter")
    func tagsRoundTrip() throws {
        let note = NoteRecord(title: "Test", body: "Hello", tags: ["auth", "bug-fix"])
        let encoded = NoteFrontmatter.encode(record: note)
        #expect(encoded.contains("tags: [auth, bug-fix]"))
        let decoded = try NoteFrontmatter.decode(from: encoded)
        #expect(decoded.tags == ["auth", "bug-fix"])
    }
}
