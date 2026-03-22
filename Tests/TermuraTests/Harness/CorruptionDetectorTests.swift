import Testing
@testable import Termura

@Suite("CorruptionDetector")
struct CorruptionDetectorTests {

    private func makeDetector() -> CorruptionDetector {
        CorruptionDetector()
    }

    @Test("Detects duplicate headings as redundancy")
    func detectRedundancy() async {
        let sections = [
            RuleSection(heading: "Error Handling", level: 2, body: "body1", lineRange: 1...5),
            RuleSection(heading: "Error Handling", level: 2, body: "body2", lineRange: 10...15)
        ]
        let detector = makeDetector()
        let results = await detector.scan(sections: sections, projectRoot: "/tmp")
        let redundancies = results.filter { $0.category == .redundancy }
        #expect(!redundancies.isEmpty)
    }

    @Test("Detects contradictory must/must not")
    func detectContradiction() async {
        let sections = [
            RuleSection(
                heading: "Rules",
                level: 2,
                body: "You must use async/await. You must not use callbacks.",
                lineRange: 1...5
            )
        ]
        let detector = makeDetector()
        let results = await detector.scan(sections: sections, projectRoot: "/tmp")
        let contradictions = results.filter { $0.category == .contradiction }
        #expect(!contradictions.isEmpty)
    }

    @Test("Clean sections produce no results")
    func cleanSections() async {
        let sections = [
            RuleSection(heading: "Style", level: 2, body: "Use 4-space indentation.", lineRange: 1...3),
            RuleSection(heading: "Testing", level: 2, body: "Write unit tests.", lineRange: 4...6)
        ]
        let detector = makeDetector()
        let results = await detector.scan(sections: sections, projectRoot: "/tmp")
        #expect(results.isEmpty)
    }
}
