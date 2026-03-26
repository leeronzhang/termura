import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NotesViewModel")

@Observable @MainActor
final class NotesViewModel {
    private(set) var notes: [NoteRecord] = []
    private(set) var snippets: [NoteRecord] = []
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

    init(repository: any NoteRepositoryProtocol) {
        self.repository = repository
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

    func createNote() {
        let note = NoteRecord(title: "Untitled")
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        editingTitle = note.title
        editingBody = note.body
        // Lifecycle: fire-and-forget persistence — note is already in the in-memory array.
        Task {
            do {
                try await repository.save(note)
            } catch {
                errorMessage = "Failed to create note: \(error.localizedDescription)"
                logger.error("Failed to create note: \(error)")
            }
        }
    }

    func selectNote(id: NoteID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        selectedNoteID = id
        editingTitle = note.title
        editingBody = note.body
    }

    func deleteNote(id: NoteID) {
        notes.removeAll { $0.id == id }
        if selectedNoteID == id {
            selectedNoteID = notes.first?.id
            if let next = selectedNoteID { selectNote(id: next) }
        }
        // Lifecycle: fire-and-forget persistence — note is already removed from in-memory array.
        Task {
            do {
                try await repository.delete(id: id)
            } catch {
                errorMessage = "Failed to delete note: \(error.localizedDescription)"
                logger.error("Failed to delete note: \(error)")
            }
        }
    }

    // MARK: - Snippets

    func loadSnippets() async {
        do {
            snippets = try await repository.fetchSnippets()
        } catch {
            errorMessage = "Failed to load snippets: \(error.localizedDescription)"
            logger.error("Failed to load snippets: \(error)")
        }
    }

    func createSnippet(title: String, body: String) {
        let snippet = NoteRecord(title: title, body: body, isSnippet: true)
        snippets.insert(snippet, at: 0)
        // Lifecycle: fire-and-forget persistence — snippet is already in the in-memory array.
        Task {
            do {
                try await repository.save(snippet)
            } catch {
                errorMessage = "Failed to save snippet: \(error.localizedDescription)"
                logger.error("Failed to save snippet: \(error)")
            }
        }
    }

    func deleteSnippet(id: NoteID) {
        snippets.removeAll { $0.id == id }
        // Lifecycle: fire-and-forget persistence — snippet is already removed from in-memory array.
        Task {
            do {
                try await repository.delete(id: id)
            } catch {
                errorMessage = "Failed to delete snippet: \(error.localizedDescription)"
                logger.error("Failed to delete snippet: \(error)")
            }
        }
    }

    func searchSnippets(query: String) async -> [NoteRecord] {
        do {
            return try await repository.searchSnippets(query: query)
        } catch {
            errorMessage = "Failed to search snippets: \(error.localizedDescription)"
            logger.error("Failed to search snippets: \(error)")
            return []
        }
    }

    // MARK: - Private

    /// Debounces title/body edits before persisting to the repository.
    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(AppConfig.Runtime.notesAutoSaveSeconds))
            } catch { return }
            guard let self else { return }
            persistCurrentNote(title: editingTitle, body: editingBody)
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
}
