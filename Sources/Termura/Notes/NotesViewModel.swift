import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NotesViewModel")

@Observable @MainActor
final class NotesViewModel {
    var notes: [NoteRecord] = []
    var selectedNoteID: NoteID?
    var editingTitle: String = "" {
        didSet {
            guard !isLoadingNote else { return }
            syncInMemoryTitle(editingTitle)
            scheduleAutoSave()
        }
    }

    var editingBody: String = "" {
        didSet {
            guard !isLoadingNote else { return }
            syncInMemoryBody(editingBody)
            scheduleAutoSave()
        }
    }

    /// User-visible error message from the last failed operation; cleared on next success.
    var errorMessage: String?

    let repository: any NoteRepositoryProtocol
    let clock: any AppClock
    @ObservationIgnored var autoSaveTask: Task<Void, Never>?
    /// True while `selectNote` is loading content into `editingTitle`/`editingBody`
    /// to suppress the spurious auto-save triggered by those assignments.
    var isLoadingNote = false
    /// Tracks in-flight persistence Tasks so they can be awaited during flush.
    /// Keyed by UUID so each Task can remove itself upon completion (self-pruning).
    @ObservationIgnored var pendingWrites: [UUID: Task<Void, Never>] = [:]
    /// Tracks the pendingWrites key for the current in-flight note save so that
    /// a new save can cancel the prior one instead of stacking up duplicate writes.
    var noteSavePendingID: UUID?
    /// Transient message shown in a toast banner after a silent note creation (e.g. "Send to Notes").
    /// Nil when no toast is active.
    var toastMessage: String?
    @ObservationIgnored private var toastDismissTask: Task<Void, Never>?
    /// ID of the most recently silently-created note. Used by the toast tap-to-navigate action.
    @ObservationIgnored var lastSilentNoteID: NoteID?

    /// Directory URL where note Markdown files are stored. Nil for legacy GRDB-only repositories.
    let notesDirectoryURL: URL?

    init(repository: any NoteRepositoryProtocol, clock: any AppClock = LiveClock(),
         notesDirectoryURL: URL? = nil) { // Optional: nil for legacy/mock repositories
        self.repository = repository
        self.clock = clock
        self.notesDirectoryURL = notesDirectoryURL
    }

    deinit {
        autoSaveTask?.cancel()
        toastDismissTask?.cancel()
        pendingWrites.values.forEach { $0.cancel() }
    }

    /// The currently selected note record, if any.
    var selectedNote: NoteRecord? {
        guard let id = selectedNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    /// File path of the currently selected note, if backed by a Markdown file.
    /// Delegates to `NoteFileService.filename(for:)` — single source of truth for slug logic.
    var selectedNoteFilePath: String? {
        guard let note = selectedNote, let dir = notesDirectoryURL else { return nil }
        let filename = NoteFileService.filename(for: note)
        return dir.appendingPathComponent(filename).path
    }

    /// Find the note record matching a file URL inside `notesDirectoryURL`.
    /// Used by LinkRouter to resolve terminal Cmd+Click on `.md` files to a NoteID.
    /// Loads notes lazily if the in-memory list is empty.
    func findNote(byFileURL url: URL) async -> NoteRecord? {
        if notes.isEmpty {
            await loadNotes()
        }
        let targetFilename = url.lastPathComponent
        return notes.first { note in
            NoteFileService.filename(for: note) == targetFilename
        }
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

    /// Shows a transient toast banner with `message` and auto-dismisses after the configured delay.
    /// Cancels any in-flight dismiss task before scheduling a new one.
    func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: AppConfig.Runtime.toastAutoDismiss)
                self?.toastMessage = nil
            } catch is CancellationError {
                // Expected: superseded by a newer showToast call.
            } catch {
                logger.warning("Toast dismiss sleep failed unexpectedly: \(error)")
            }
        }
    }

    func selectNote(id: NoteID) {
        // Already editing this note — keep current edits, skip reload.
        // Prevents the debounce race: view recreation calls selectNote with
        // the same ID before auto-save fires, overwriting unsaved edits with
        // stale data from the in-memory notes array.
        if selectedNoteID == id { return }

        // Flush pending edits for the departing note before switching so that
        // a rename-then-select within 1 second does not lose the rename.
        if selectedNoteID != nil, autoSaveTask != nil {
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
}
