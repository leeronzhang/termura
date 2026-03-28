import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NotesViewModel")

@Observable @MainActor
final class NotesViewModel {
    private(set) var notes: [NoteRecord] = []
    var selectedNoteID: NoteID?
    var editingTitle: String = "" {
        didSet { scheduleAutoSave() }
    }

    var editingBody: String = "" {
        didSet { scheduleAutoSave() }
    }

    /// User-visible error message from the last failed operation; cleared on next success.
    var errorMessage: String?

    private let repository: any NoteRepositoryProtocol
    private var saveTask: Task<Void, Never>?
    private var autoSaveTask: Task<Void, Never>?
    /// Tracks in-flight persistence Tasks so they can be awaited during flush.
    /// Keyed by UUID so each Task can remove itself upon completion (self-pruning).
    private var pendingWrites: [UUID: Task<Void, Never>] = [:]

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
        guard let note = notes.first(where: { $0.id == id }) else { return }
        selectedNoteID = id
        editingTitle = note.title
        editingBody = note.body
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

    func deleteNote(id: NoteID) {
        notes.removeAll { $0.id == id }
        if selectedNoteID == id {
            selectedNoteID = notes.first?.id
            if let next = selectedNoteID { selectNote(id: next) }
        }
        persistTracked { [repository] in
            try await repository.delete(id: id)
        }
    }

    // MARK: - Private

    /// Debounces title/body edits before persisting to the repository.
    private func scheduleAutoSave() {
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
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.save(updated)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Auto-save failed: \(error.localizedDescription)"
                    logger.error("Note auto-save failed: \(error)")
                }
            }
        }
    }

    // MARK: - Tracked persistence

    /// Persists an operation asynchronously while tracking the Task for flush.
    private func persistTracked(
        _ operation: @Sendable @escaping () async throws -> Void
    ) {
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
    }

    /// Awaits all in-flight persistence Tasks and force-saves the currently
    /// edited note to capture any debounced changes not yet written to DB.
    func flushPendingWrites() async {
        // 1. Cancel debounce timers.
        autoSaveTask?.cancel()
        autoSaveTask = nil
        saveTask?.cancel()
        saveTask = nil

        // 2. Await all tracked writes.
        let snapshot = Array(pendingWrites.values)
        pendingWrites.removeAll()
        for task in snapshot {
            await task.value
        }

        // 3. Force-save the currently edited note to capture debounced edits.
        if let id = selectedNoteID,
           let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].title = editingTitle
            notes[idx].body = editingBody
            notes[idx].updatedAt = Date()
            do {
                try await repository.save(notes[idx])
            } catch {
                logger.error("Flush note save error: \(error)")
            }
        }
    }
}
