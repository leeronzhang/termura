import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NotesViewModel")

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var notes: [NoteRecord] = []
    @Published var selectedNoteID: NoteID?
    @Published var editingTitle: String = ""
    @Published var editingBody: String = ""

    private let repository: any NoteRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    private var saveTask: Task<Void, Never>?

    init(repository: any NoteRepositoryProtocol) {
        self.repository = repository
        setupAutoSave()
    }

    func loadNotes() async {
        do {
            notes = try await repository.fetchAll()
        } catch {
            logger.error("Failed to load notes: \(error)")
        }
    }

    func createNote() {
        let note = NoteRecord(title: "Untitled")
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        editingTitle = note.title
        editingBody = note.body
        Task {
            do {
                try await repository.save(note)
            } catch {
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
        Task {
            do {
                try await repository.delete(id: id)
            } catch {
                logger.error("Failed to delete note: \(error)")
            }
        }
    }

    // MARK: - Private

    private func setupAutoSave() {
        Publishers.CombineLatest($editingTitle, $editingBody)
            .debounce(
                for: .seconds(AppConfig.Runtime.notesAutoSaveSeconds),
                scheduler: RunLoop.main
            )
            .dropFirst()
            .sink { [weak self] title, body in
                self?.persistCurrentNote(title: title, body: body)
            }
            .store(in: &cancellables)
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
                    logger.error("Note auto-save failed: \(error)")
                }
            }
        }
    }
}
