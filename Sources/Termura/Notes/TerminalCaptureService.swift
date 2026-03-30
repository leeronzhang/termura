import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalCaptureService")

/// Converts an OutputChunk to a fenced Markdown code block and appends it to the active note.
@MainActor
final class TerminalCaptureService {
    private let noteRepository: any NoteRepositoryProtocol
    private let notesViewModel: NotesViewModel

    init(noteRepository: any NoteRepositoryProtocol, notesViewModel: NotesViewModel) {
        self.noteRepository = noteRepository
        self.notesViewModel = notesViewModel
    }

    func capture(_ chunk: OutputChunk) {
        let markdown = formatAsMarkdown(chunk)
        if notesViewModel.selectedNoteID != nil {
            notesViewModel.editingBody += "\n\n" + markdown
        } else {
            notesViewModel.createNote(body: markdown)
        }
        logger.info("Captured chunk '\(chunk.commandText)' to note")
    }

    // MARK: - Private

    private func formatAsMarkdown(_ chunk: OutputChunk) -> String {
        let exitStr = chunk.exitCode.map(String.init) ?? "\u{2014}"
        let header = "#### `\(chunk.commandText)` (exit: \(exitStr))"
        let body = chunk.outputLines.joined(separator: "\n")
        return "\(header)\n\n```\n\(body)\n```"
    }
}
