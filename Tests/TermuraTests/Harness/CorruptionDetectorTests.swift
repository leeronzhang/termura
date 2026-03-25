import Foundation
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

    // MARK: - Stale file paths

    @Test("Detects stale file reference with path separator")
    func detectStaleFilePath() async throws {
        let tmpDir = NSTemporaryDirectory() + "corruption-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let sections = [
            RuleSection(
                heading: "Config",
                level: 2,
                body: "See `src/config/missing.swift` for details.",
                lineRange: 1 ... 3
            )
        ]
        let detector = makeDetector()
        let results = await detector.scan(sections: sections, projectRoot: tmpDir)
        let stale = results.filter { $0.category == .stalePath }
        #expect(!stale.isEmpty)
        #expect(stale.first?.message.contains("missing.swift") ?? false)
    }

    @Test("Does not flag existing file as stale")
    func existingFileNotStale() async throws {
        let tmpDir = NSTemporaryDirectory() + "corruption-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tmpDir + "/src",
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let filePath = tmpDir + "/src/real.swift"
        try "content".write(toFile: filePath, atomically: true, encoding: .utf8)

        let sections = [
            RuleSection(
                heading: "Config",
                level: 2,
                body: "See `src/real.swift` for details.",
                lineRange: 1 ... 3
            )
        ]
        let detector = makeDetector()
        let results = await detector.scan(sections: sections, projectRoot: tmpDir)
        let stale = results.filter { $0.category == .stalePath }
        #expect(stale.isEmpty)
    }

    @Test("Ignores file references without path separator")
    func ignoresBareFileNames() async {
        let sections = [
            RuleSection(
                heading: "Config",
                level: 2,
                body: "See `README.md` for details.",
                lineRange: 1 ... 3
            )
        ]
        let detector = makeDetector()
        let results = await detector.scan(sections: sections, projectRoot: "/tmp")
        let stale = results.filter { $0.category == .stalePath }
        #expect(stale.isEmpty)
    }

    // MARK: - Contradiction edge cases

    @Test("No contradiction when only 'must' without 'must not'")
    func mustAloneNoContradiction() async {
        let sections = [
            RuleSection(
                heading: "Rules",
                level: 2,
                body: "You must use structured concurrency.",
                lineRange: 1 ... 3
            )
        ]
        let detector = makeDetector()
        let results = await detector.scan(sections: sections, projectRoot: "/tmp")
        let contradictions = results.filter { $0.category == .contradiction }
        #expect(contradictions.isEmpty)
    }

    // MARK: - Redundancy edge cases

    @Test("Case-insensitive heading dedup")
    func caseInsensitiveRedundancy() async {
        let sections = [
            RuleSection(heading: "Error Handling", level: 2, body: "v1", lineRange: 1 ... 3),
            RuleSection(heading: "error handling", level: 2, body: "v2", lineRange: 5 ... 7)
        ]
        let detector = makeDetector()
        let results = await detector.scan(sections: sections, projectRoot: "/tmp")
        let redundancies = results.filter { $0.category == .redundancy }
        #expect(!redundancies.isEmpty)
    }

    @Test("Different headings produce no redundancy")
    func differentHeadingsNoRedundancy() async {
        let sections = [
            RuleSection(heading: "Error Handling", level: 2, body: "v1", lineRange: 1 ... 3),
            RuleSection(heading: "Testing", level: 2, body: "v2", lineRange: 5 ... 7)
        ]
        let detector = makeDetector()
        let results = await detector.scan(sections: sections, projectRoot: "/tmp")
        let redundancies = results.filter { $0.category == .redundancy }
        #expect(redundancies.isEmpty)
    }

    @Test("Empty sections produce no results")
    func emptySections() async {
        let detector = makeDetector()
        let results = await detector.scan(sections: [], projectRoot: "/tmp")
        #expect(results.isEmpty)
    }
}
