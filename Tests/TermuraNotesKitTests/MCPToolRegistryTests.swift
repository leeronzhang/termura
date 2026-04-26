import Foundation
@testable import TermuraNotesKit
import Testing

@Suite("MCPToolRegistry")
struct MCPToolRegistryTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func seedNote(title: String, body: String, in dir: URL) throws -> NoteRecord {
        let lister = NoteFileLister()
        var note = NoteRecord(title: title, body: body)
        note.createdAt = fixedDate
        note.updatedAt = fixedDate
        _ = try lister.writeNote(note, to: dir)
        return note
    }

    private func makeRegistry(dir: URL) -> MCPToolRegistry {
        MCPToolRegistry(lister: NoteFileLister(), notesDirectory: dir)
    }

    // MARK: - list_notes

    @Test("list_notes returns all seeded notes")
    func testListNotes() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try seedNote(title: "Alpha", body: "First note", in: dir)
        _ = try seedNote(title: "Beta", body: "Second note", in: dir)

        let result = makeRegistry(dir: dir).call(name: "list_notes", arguments: [:], now: fixedDate)
        #expect(!result.isError)
        let items = try JSONDecoder().decode([ListItem].self, from: Data(result.content[0].text.utf8))
        #expect(items.count == 2)
    }

    // MARK: - read_note

    @Test("read_note returns body for existing note")
    func readNote() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try seedNote(title: "Read Me", body: "Hello world", in: dir)

        let result = makeRegistry(dir: dir).call(
            name: "read_note",
            arguments: ["identifier": .string("Read Me")],
            now: fixedDate
        )
        #expect(!result.isError)
        #expect(result.content[0].text.contains("Hello world"))
    }

    @Test("read_note returns error for missing note")
    func readNoteMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = makeRegistry(dir: dir).call(
            name: "read_note",
            arguments: ["identifier": .string("Nope")],
            now: fixedDate
        )
        #expect(result.isError)
        #expect(result.content[0].text.contains("not found"))
    }

    @Test("read_note returns error when identifier missing")
    func readNoteMissingParam() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = makeRegistry(dir: dir).call(name: "read_note", arguments: [:], now: fixedDate)
        #expect(result.isError)
        #expect(result.content[0].text.contains("identifier"))
    }

    // MARK: - search_notes

    @Test("search_notes finds matching note")
    func searchNotes() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try seedNote(title: "Unique Title", body: "Some content here", in: dir)
        _ = try seedNote(title: "Other", body: "Nothing relevant", in: dir)

        let result = makeRegistry(dir: dir).call(
            name: "search_notes",
            arguments: ["query": .string("Unique")],
            now: fixedDate
        )
        #expect(!result.isError)
        #expect(result.content[0].text.contains("Unique Title"))
    }

    // MARK: - create_note

    @Test("create_note creates a new note file")
    func createNote() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = makeRegistry(dir: dir).call(
            name: "create_note",
            arguments: ["title": .string("New Note"), "body": .string("Fresh content")],
            now: fixedDate
        )
        #expect(!result.isError)
        #expect(result.content[0].text.contains("Created"))

        let notes = try NoteFileLister().listNotes(in: dir)
        #expect(notes.count == 1)
        #expect(notes[0].title == "New Note")
    }

    // MARK: - append_to_note

    @Test("append_to_note appends content to existing note")
    func appendToNote() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try seedNote(title: "Append Target", body: "Original.", in: dir)

        let result = makeRegistry(dir: dir).call(
            name: "append_to_note",
            arguments: ["identifier": .string("Append Target"), "content": .string("Added line.")],
            now: fixedDate
        )
        #expect(!result.isError)

        let (updated, _) = try NoteFileLister().findNote(byTitle: "Append Target", in: dir)!
        #expect(updated.body.contains("Added line."))
        #expect(updated.body.contains("Original."))
    }

    // MARK: - link_notes

    @Test("link_notes adds backlink between notes")
    func linkNotes() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try seedNote(title: "Source", body: "Start.", in: dir)
        _ = try seedNote(title: "Target", body: "End.", in: dir)

        let result = makeRegistry(dir: dir).call(
            name: "link_notes",
            arguments: ["from": .string("Source"), "to": .string("Target")],
            now: fixedDate
        )
        #expect(!result.isError)
        #expect(result.content[0].text.contains("Linked"))

        let (linked, _) = try NoteFileLister().findNote(byTitle: "Source", in: dir)!
        #expect(linked.body.contains("[[Target]]"))
    }

    @Test("link_notes is idempotent")
    func linkNotesIdempotent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try seedNote(title: "A", body: "Content.", in: dir)
        _ = try seedNote(title: "B", body: "Other.", in: dir)

        let registry = makeRegistry(dir: dir)
        _ = registry.call(name: "link_notes", arguments: ["from": .string("A"), "to": .string("B")], now: fixedDate)
        let result = registry.call(
            name: "link_notes",
            arguments: ["from": .string("A"), "to": .string("B")],
            now: fixedDate
        )
        #expect(!result.isError)
        #expect(result.content[0].text.contains("already exists"))
    }

    @Test("unknown tool returns error")
    func unknownTool() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = makeRegistry(dir: dir).call(name: "fake_tool", arguments: [:], now: fixedDate)
        #expect(result.isError)
    }
}

// Minimal DTO for decoding list_notes output
private struct ListItem: Decodable {
    let id: String
    let title: String
}
