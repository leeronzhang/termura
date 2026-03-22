import Testing
@testable import Termura

@Suite("RuleFileParser")
struct RuleFileParserTests {

    @Test("Parses headings into sections")
    func parseHeadings() {
        let content = """
            # Title
            Some intro text.

            ## Section One
            Body of section one.

            ## Section Two
            Body of section two.
            """
        let sections = RuleFileParser.parse(content)
        #expect(sections.count == 3)
        #expect(sections[0].heading == "Title")
        #expect(sections[0].level == 1)
        #expect(sections[1].heading == "Section One")
        #expect(sections[1].level == 2)
        #expect(sections[2].heading == "Section Two")
    }

    @Test("Preserves body content")
    func parseBody() {
        let content = """
            ## Rules
            - Rule one
            - Rule two
            - Rule three
            """
        let sections = RuleFileParser.parse(content)
        #expect(sections.count == 1)
        #expect(sections[0].body.contains("Rule one"))
        #expect(sections[0].body.contains("Rule three"))
    }

    @Test("Empty content returns empty sections")
    func parseEmpty() {
        let sections = RuleFileParser.parse("")
        #expect(sections.isEmpty)
    }

    @Test("Content without headings returns empty sections")
    func parseNoHeadings() {
        let sections = RuleFileParser.parse("Just some text\nwithout any headings")
        #expect(sections.isEmpty)
    }

    @Test("Handles h3-h6 levels")
    func parseDeepHeadings() {
        let content = """
            ### Level 3
            body3
            #### Level 4
            body4
            """
        let sections = RuleFileParser.parse(content)
        #expect(sections.count == 2)
        #expect(sections[0].level == 3)
        #expect(sections[1].level == 4)
    }

    @Test("Line ranges are correct")
    func lineRanges() {
        let content = "# A\nline1\nline2\n## B\nline3"
        let sections = RuleFileParser.parse(content)
        #expect(sections.count == 2)
        #expect(sections[0].lineRange.lowerBound == 1)
        #expect(sections[1].lineRange.lowerBound == 4)
    }
}
