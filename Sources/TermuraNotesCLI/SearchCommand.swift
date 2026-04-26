import ArgumentParser
import Foundation
import TermuraNotesKit

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search notes by content."
    )

    @Argument(help: "Search query.")
    var query: String

    @Flag(name: .long, help: "Output as JSON for programmatic use.")
    var json = false

    func run() throws {
        let project = try ProjectDiscovery()
        let lister = NoteFileLister()
        let results = try lister.searchNotes(query: query, in: project.notesDirectory)

        if results.isEmpty {
            print("No results for \"\(query)\".")
            return
        }

        if json {
            printJSON(results)
        } else {
            printHuman(results)
        }
    }

    private func printHuman(_ results: [(note: NoteRecord, matches: [String])]) {
        for (note, matches) in results {
            let idPrefix = String(note.id.rawValue.uuidString.prefix(8)).lowercased()
            print("\(idPrefix)  \(note.title.isEmpty ? "(untitled)" : note.title)")
            for match in matches.prefix(3) {
                print("  \(match)")
            }
        }
        print("\n\(results.count) note(s) matched.")
    }

    private func printJSON(_ results: [(note: NoteRecord, matches: [String])]) {
        var items: [[String: Any]] = []
        for (note, matches) in results {
            items.append([
                "id": note.id.rawValue.uuidString,
                "title": note.title,
                "matches": matches
            ])
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } catch {
            FileHandle.standardError.write(Data("Failed to serialize JSON: \(error.localizedDescription)\n".utf8))
        }
    }
}
