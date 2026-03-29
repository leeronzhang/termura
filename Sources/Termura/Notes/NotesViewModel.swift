import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NotesViewModel")

@Observable @MainActor
final class NotesViewModel {
    private(set) var notes: [NoteRecord] = []
    var selectedNoteID: NoteID?
    var editingTitle: String = "" {
        didSet {
            guard !isLoadingNote else { return }
            syncInMemoryTitle(editingTitle)
            scheduleAutoSave()
        }
    }

    var editingBody: String = "" {
        didSet { scheduleAutoSave() }
    }

    /// User-visible error message from the last failed operation; cleared on next success.
    var errorMessage: String?

    private let repository: any NoteRepositoryProtocol
    private var autoSaveTask: Task<Void, Never>?
    /// True while `selectNote` is loading content into `editingTitle`/`editingBody`
    /// to suppress the spurious auto-save triggered by those assignments.
    private var isLoadingNote = false
    /// Tracks in-flight persistence Tasks so they can be awaited during flush.
    /// Keyed by UUID so each Task can remove itself upon completion (self-pruning).
    private var pendingWrites: [UUID: Task<Void, Never>] = [:]
    /// Tracks the pendingWrites key for the current in-flight note save so that
    /// a new save can cancel the prior one instead of stacking up duplicate writes.
    private var noteSavePendingID: UUID?

    init(repository: any NoteRepositoryProtocol) {
        self.repository = repository
    }

    /// The currently selected note record, if any.
    var selectedNote: NoteRecord? {
        guard let id = selectedNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    func loadNotes() async {
        do {
            notes = try await repository.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load notes: \(error.localizedDescription)"
            logger.error("Failed to load notes: \(error)")
        }
    }

    func createNote(title: String = "Untitled", body: String = "") {
        let note = NoteRecord(title: title, body: body)
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        editingTitle = note.title
        editingBody = note.body
        persistTracked { [repository] in
            try await repository.save(note)
        }
    }

    func selectNote(id: NoteID) {
        // Flush pending edits for the departing note before switching so that
        // a rename-then-select within 1 second does not lose the rename.
        if selectedNoteID != nil, selectedNoteID != id, autoSaveTask != nil {
            autoSaveTask?.cancel()
            autoSaveTask = nil
            persistCurrentNote(title: editingTitle, body: editingBody)
        }
        guard let note = notes.first(where: { $0.id == id }) else { return }
        // Load content without triggering auto-save — these assignments are
        // restoring stored state, not user edits.
        isLoadingNote = true
        selectedNoteID = id
        editingTitle = note.title
        editingBody = note.body
        isLoadingNote = false
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

    // MARK: - Private

    /// Immediately reflects the new title into the in-memory notes array so that
    /// the sidebar list updates while the user is typing, without waiting for the
    /// debounced persistence to fire.
    private func syncInMemoryTitle(_ title: String) {
        guard let id = selectedNoteID,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].title = title
    }

    /// Debounces title/body edits before persisting to the repository.
    private func scheduleAutoSave() {
        guard !isLoadingNote else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: AppConfig.Runtime.notesAutoSave)
            } catch {
                // CancellationError is expected — next edit restarts the debounce.
                return
            }
            guard let self else { return }
            persistCurrentNote(title: editingTitle, body: editingBody)
        }
    }

    /// Re-sorts notes array: favorites first, then by updatedAt descending.
    private func resortNotes() {
        notes.sort { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func persistCurrentNote(title: String, body: String) {
        guard let id = selectedNoteID,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].title = title
        notes[idx].body = body
        notes[idx].updatedAt = Date()
        let updated = notes[idx]
        // Cancel any prior in-flight note save before registering a fresh one so
        // rapid edits do not stack up duplicate writes in pendingWrites.
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
    private func persistTracked(
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
        // 1. Cancel the debounce timer. Any in-flight note save is already
        //    registered in pendingWrites and will be awaited in step 2.
        autoSaveTask?.cancel()
        autoSaveTask = nil

        // 2. Await all tracked writes (includes any in-flight note save).
        let snapshot = Array(pendingWrites.values)
        pendingWrites.removeAll()
        noteSavePendingID = nil
        for task in snapshot {
            await task.value
        }

        // 3. Force-save the currently edited note to capture changes that were
        //    still in the debounce window (autoSaveTask cancelled before firing).
        if let id = selectedNoteID,
           let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].title = editingTitle
            notes[idx].body = editingBody
            notes[idx].updatedAt = Date()
            do {
                try await repository.save(notes[idx])
            } catch {
                errorMessage = "Failed to save note: \(error.localizedDescription)"
                logger.error("Flush note save error: \(error)")
            }
        }
    }
}
