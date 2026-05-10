import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NotesViewModel.Ops")

extension NotesViewModel {
    @discardableResult
    func createNote(title: String = "Untitled", body: String = "") -> NoteRecord {
        let note = NoteRecord(title: title, body: body)
        notes.insert(note, at: 0)
        // Suppress editingTitle/editingBody didSet — these assignments are
        // initialising the new note, not user edits. Without this fence, the
        // didSet schedules a 1s autosave whose stale "Untitled"/"" snapshot
        // can survive a subsequent selection change and overwrite the next
        // selected note's content.
        isLoadingNote = true
        selectedNoteID = note.id
        editingTitle = note.title
        editingBody = note.body
        isLoadingNote = false
        enqueueChainedSave(note)
        return note
    }

    /// Creates and persists a note without modifying the current selection or editing state.
    /// Used when programmatically inserting notes (e.g. "Send to Notes" from terminal context menu)
    /// so the user's active note editing session is not interrupted.
    func silentlyCreateNote(title: String, body: String) {
        let note = NoteRecord(title: title, body: body)
        notes.insert(note, at: 0)
        lastSilentNoteID = note.id
        enqueueChainedSave(note)
    }

    func toggleFavorite(id: NoteID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].isFavorite.toggle()
        let updated = notes[idx]
        resortNotes()
        enqueueChainedSave(updated)
    }

    func deleteNote(id: NoteID) async {
        let isDeletingSelected = (selectedNoteID == id)

        // Cancel the selected note's debounced autosave so it can't fire
        // mid-delete and persist its stale title/body onto whatever note we
        // switch to afterwards (the data-loss path users observed).
        if isDeletingSelected {
            autoSaveTask?.cancel()
            autoSaveTask = nil
        }

        // Drain the save chain so a pending save targeting this id can't run
        // after `repository.delete` and resurrect the row. Awaiting the chain
        // head is sufficient — every chain link starts with `await previous?
        // .value`, so head-await transitively waits for every prior save.
        let chainHead = noteSavePendingID.flatMap { pendingWrites[$0] }
        await chainHead?.value

        do {
            try await repository.delete(id: id)
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
            logger.error("DB delete failed for note \(id): \(error)")
            return
        }
        notes.removeAll { $0.id == id }

        guard isDeletingSelected else { return }
        if let next = notes.first?.id {
            // Leave selectedNoteID pointing at the deleted id so selectNote's
            // `if selectedNoteID == id { return }` early-return does not trip;
            // selectNote then atomically loads `next`'s title/body into the
            // editing buffers under its own isLoadingNote fence.
            selectNote(id: next)
        } else {
            isLoadingNote = true
            selectedNoteID = nil
            editingTitle = ""
            editingBody = ""
            isLoadingNote = false
        }
    }
}
