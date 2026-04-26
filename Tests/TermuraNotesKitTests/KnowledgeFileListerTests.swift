import Foundation
@testable import TermuraNotesKit
import Testing

@Suite("KnowledgeFileLister")
struct KnowledgeFileListerTests {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowledgeFileListerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Sources

    @Test("listSources returns files grouped by subdirectory")
    func sourcesHappyPath() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let articles = root.appendingPathComponent("articles")
        try FileManager.default.createDirectory(at: articles, withIntermediateDirectories: true)
        try "Hello".write(to: articles.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        try "World".write(to: articles.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let code = root.appendingPathComponent("code")
        try FileManager.default.createDirectory(at: code, withIntermediateDirectories: true)
        try "fn main".write(to: code.appendingPathComponent("snippet.rs"), atomically: true, encoding: .utf8)

        let entries = KnowledgeFileLister.listSources(in: root)
        #expect(entries.count == 3)

        let articleEntries = entries.filter { $0.category == "articles" }
        #expect(articleEntries.count == 2)

        let codeEntries = entries.filter { $0.category == "code" }
        #expect(codeEntries.count == 1)
        #expect(codeEntries.first?.name == "snippet.rs")
    }

    @Test("listSources on empty directory returns empty")
    func sourcesEmpty() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        let entries = KnowledgeFileLister.listSources(in: root)
        #expect(entries.isEmpty)
    }

    @Test("listSources on nonexistent directory returns empty")
    func sourcesNonexistent() {
        let fake = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)")
        let entries = KnowledgeFileLister.listSources(in: fake)
        #expect(entries.isEmpty)
    }

    // MARK: - Logs

    @Test("listLogs returns files grouped by date directory, newest first")
    func logsHappyPath() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let day1 = root.appendingPathComponent("2026-04-25")
        try FileManager.default.createDirectory(at: day1, withIntermediateDirectories: true)
        try "session 1".write(to: day1.appendingPathComponent("10-00-chat.md"), atomically: true, encoding: .utf8)

        let day2 = root.appendingPathComponent("2026-04-26")
        try FileManager.default.createDirectory(at: day2, withIntermediateDirectories: true)
        try "session 2".write(to: day2.appendingPathComponent("14-30-refactor.md"), atomically: true, encoding: .utf8)
        try "session 3".write(to: day2.appendingPathComponent("16-00-debug.md"), atomically: true, encoding: .utf8)

        let entries = KnowledgeFileLister.listLogs(in: root)
        #expect(entries.count == 3)

        // Newest date first
        #expect(entries.first?.category == "2026-04-26")
        #expect(entries.last?.category == "2026-04-25")
    }

    @Test("listLogs on empty directory returns empty")
    func logsEmpty() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        let entries = KnowledgeFileLister.listLogs(in: root)
        #expect(entries.isEmpty)
    }
}
