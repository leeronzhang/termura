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
        let updated = notes[idx]
        if let oldID = noteSavePendingID {
            pendingWrites[oldID]?.cancel()
            pendingWrites.removeValue(forKey: oldID)
        }
        noteSavePendingID = persistTracked { [repository] in
            try await repository.save(updated)
        }
    }

    // MARK: - Tracked persistence

    /// Persists an operation asynchronously while tracking the Task for flush.
    /// Returns the UUID key under which the task is registered in `pendingWrites`,
    /// so callers can cancel a prior task before registering a replacement.
    @discardableResult
    func persistTracked(
        _ operation: @Sendable @escaping () async throws -> Void
    ) -> UUID {
        let id = UUID()
        let task = Task { [weak self] in
            defer { self?.pendingWrites.removeValue(forKey: id) }
            do {
                try await operation()
            } catch {
                self?.errorMessage = "\(error.localizedDescription)"
                logger.error("Persistence error: \(error)")
            }
        }
        pendingWrites[id] = task
        return id
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
