import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NotesViewModel.Persistence")

extension NotesViewModel {
    /// Immediately reflects the new title into the in-memory notes array so that
    /// the sidebar list updates while the user is typing, without waiting for the
    /// debounced persistence to fire.
    func syncInMemoryTitle(_ title: String) {
        guard let id = selectedNoteID,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].title = title
    }

    /// Immediately reflects the new body into the in-memory notes array so that
    /// `selectNote` (and any other reader of `notes[idx].body`) sees the latest
    /// content even before the debounced persistence fires.
    func syncInMemoryBody(_ body: String) {
        guard let id = selectedNoteID,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].body = body
    }

    /// Debounces title/body edits before persisting to the repository.
    func scheduleAutoSave() {
        guard !isLoadingNote else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: AppConfig.Runtime.notesAutoSave)
            } catch {
                // CancellationError is expected — next edit restarts the debounce.
                return
            }
            persistCurrentNote(title: editingTitle, body: editingBody)
        }
    }

    /// Re-sorts notes array using canonical display order (favorites first, then by updatedAt).
    func resortNotes() {
        notes.sort(by: NoteRecord.displayOrder)
    }

    func persistCurrentNote(title: String, body: String) {
        guard let id = selectedNoteID,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].title = title
        notes[idx].body = body
        notes[idx].updatedAt = clock.now()
        backlinkIndex.rebuild(from: notes)
        enqueueChainedSave(notes[idx])
    }

    // MARK: - Chained persistence

    /// Enqueues a `repository.save(note)` onto the serial chain shared by all
    /// note disk writes (autosave, createNote, toggleFavorite, silentlyCreateNote).
    /// Without this single chain, independent saves race on the repository actor
    /// at fileService awaits; because `FileBackedNoteRepository.save` removes the
    /// old-named file on rename, a stale save running second deleted the file a
    /// fresh save just wrote and pinned disk to the stale snapshot — the bug
    /// pattern that produced empty-bodied "Untitled" notes after rapid
    /// create-then-edit.
    ///
    /// OWNER: NotesViewModel.
    /// TEARDOWN: `flushPendingWrites` awaits the chain head before returning.
    @discardableResult
    func enqueueChainedSave(_ note: NoteRecord) -> UUID {
        let previous = noteSavePendingID.flatMap { pendingWrites[$0] }
        let trackingID = UUID()
        let task = Task { [weak self] in
            defer { self?.pendingWrites.removeValue(forKey: trackingID) }
            await previous?.value
            guard let self else { return }
            do {
                try await repository.save(note)
            } catch {
                errorMessage = "\(error.localizedDescription)"
                logger.error("Note save error: \(error)")
            }
        }
        pendingWrites[trackingID] = task
        noteSavePendingID = trackingID
        return trackingID
    }

    /// Awaits all in-flight persistence Tasks and force-saves the currently
    /// edited note to capture any debounced changes not yet written to DB.
    func flushPendingWrites() async {
        autoSaveTask?.cancel()
        autoSaveTask = nil

        let snapshot = Array(pendingWrites.values)
        pendingWrites.removeAll()
        noteSavePendingID = nil
        for task in snapshot {
            await task.value
        }

        if let id = selectedNoteID,
           let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].title = editingTitle
            notes[idx].body = editingBody
            notes[idx].updatedAt = clock.now()
            do {
                try await repository.save(notes[idx])
            } catch {
                errorMessage = "Failed to save note: \(error.localizedDescription)"
                logger.error("Flush note save error: \(error)")
            }
        }
    }
}
