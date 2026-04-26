import ArgumentParser
import Foundation
import TermuraNotesKit

struct AppendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "append",
        abstract: "Append content to an existing note."
    )

    @Option(name: .long, help: "Target note title or ID prefix.")
    var to: String

    @Argument(help: "Content to append. Omit to read from stdin.")
    var content: [String] = []

    func run() throws {
        let project = try ProjectDiscovery()
        let lister = NoteFileLister()

        guard let (note, _) = try resolveNote(title: to, lister: lister, directory: project.notesDirectory) else {
            throw ValidationError("Note not found: \(to)")
        }

        let appendText: String
        if content.isEmpty {
            guard let stdin = readLine(strippingNewline: false) else {
                throw ValidationError("No content provided. Pass content as argument or pipe via stdin.")
            }
            var lines = stdin
            while let line = readLine(strippingNewline: false) {
                lines += line
            }
            appendText = lines
        } else {
            appendText = content.joined(separator: " ")
        }

        var updated = note
        updated.body = note.body.hasSuffix("\n")
            ? note.body + appendText + "\n"
            : note.body + "\n" + appendText + "\n"
        updated.updatedAt = Date()

        _ = try lister.writeNote(updated, to: project.notesDirectory)
        print("Appended to \"\(note.title)\"")
    }
}
