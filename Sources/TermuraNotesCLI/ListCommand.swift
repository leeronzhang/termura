import ArgumentParser
import Foundation
import TermuraNotesKit

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all notes in the current project."
    )

    @Flag(name: .long, help: "Output as JSON for programmatic use.")
    var json = false

    func run() throws {
        let project = try ProjectDiscovery()
        let lister = NoteFileLister()
        let notes = try lister.listNotes(in: project.notesDirectory)

        if json {
            printJSON(notes)
        } else {
            printTable(notes)
        }
    }

    private func printTable(_ notes: [NoteRecord]) {
        if notes.isEmpty {
            print("No notes found.")
            return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        for note in notes {
            let fav = note.isFavorite ? "*" : " "
            let date = formatter.string(from: note.updatedAt)
            let title = note.title.isEmpty ? "(untitled)" : note.title
            let idPrefix = String(note.id.rawValue.uuidString.prefix(8)).lowercased()
            print("\(fav) \(idPrefix)  \(date)  \(title)")
        }
        print("\n\(notes.count) note(s)")
    }

    private func printJSON(_ notes: [NoteRecord]) {
        var items: [[String: Any]] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for note in notes {
            items.append([
                "id": note.id.rawValue.uuidString,
                "title": note.title,
                "favorite": note.isFavorite,
                "folder": note.isFolder,
                "created": formatter.string(from: note.createdAt),
                "updated": formatter.string(from: note.updatedAt)
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
