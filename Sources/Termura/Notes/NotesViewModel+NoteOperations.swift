import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NotesViewModel.Ops")

extension NotesViewModel {
    @discardableResult
    func createNote(title: String = "Untitled", body: String = "") -> NoteRecord {
        let note = NoteRecord(title: title, body: body)
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        editingTitle = note.title
        editingBody = note.body
        persistTracked { [repository] in
            try await repository.save(note)
        }
        return note
    }

    /// Creates and persists a note without modifying the current selection or editing state.
    /// Used when programmatically inserting notes (e.g. "Send to Notes" from terminal context menu)
    /// so the user's active note editing session is not interrupted.
    func silentlyCreateNote(title: String, body: String) {
        let note = NoteRecord(title: title, body: body)
        notes.insert(note, at: 0)
        lastSilentNoteID = note.id
        persistTracked { [repository] in
            try await repository.save(note)
        }
    }

    func toggleFavorite(id: NoteID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].isFavorite.toggle()
        let updated = notes[idx]
        resortNotes()
        persistTracked { [repository] in
            try await repository.save(updated)
        }
    }

    func deleteNote(id: NoteID) async {
        // DB delete first — prevents deleted notes from resurfacing on next launch
        // if the note was removed from memory before the DB operation completed.
        do {
            try await repository.delete(id: id)
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
            logger.error("DB delete failed for note \(id): \(error)")
            return
        }
        notes.removeAll { $0.id == id }
        if selectedNoteID == id {
            selectedNoteID = notes.first?.id
            if let next = selectedNoteID { selectNote(id: next) }
        }
    }
}
