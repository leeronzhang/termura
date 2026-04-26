import ArgumentParser
import Foundation
import TermuraNotesKit

struct LinkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "link",
        abstract: "Add a backlink between two notes."
    )

    @Option(name: .long, help: "Source note title or ID prefix.")
    var from: String

    @Option(name: .long, help: "Target note title (will be inserted as [[target]]).")
    var to: String

    func run() throws {
        let project = try ProjectDiscovery()
        let lister = NoteFileLister()

        guard let (note, _) = try resolveNote(title: from, lister: lister, directory: project.notesDirectory) else {
            throw ValidationError("Source note not found: \(from)")
        }

        // Verify target exists
        guard let (target, _) = try resolveNote(title: to, lister: lister, directory: project.notesDirectory) else {
            throw ValidationError("Target note not found: \(to)")
        }

        let link = "[[\(target.title)]]"
        if note.body.contains(link) {
            print("Link to \"\(target.title)\" already exists in \"\(note.title)\".")
            return
        }

        var updated = note
        updated.body = note.body.hasSuffix("\n")
            ? note.body + "\n" + link + "\n"
            : note.body + "\n\n" + link + "\n"
        updated.updatedAt = Date()

        _ = try lister.writeNote(updated, to: project.notesDirectory)
        print("Linked \"\(note.title)\" → \"\(target.title)\"")
    }
}
