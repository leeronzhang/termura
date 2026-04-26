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

    /// In-memory reverse index: maps note titles to notes that link to them via [[...]].
    @ObservationIgnored var backlinkIndex = BacklinkIndex()

    /// Currently active tag filter in Notes tab. Nil = show all notes.
    var selectedTagFilter: String?

    /// Browse mode for Knowledge tab.
    enum KnowledgeBrowseMode: String, CaseIterable, Identifiable {
        case tags, timeline, graph, sources, log
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tags: "Tags"
            case .timeline: "Timeline"
            case .graph: "Graph"
            case .sources: "Sources"
            case .log: "Log"
            }
        }
    }

    var knowledgeBrowseMode: KnowledgeBrowseMode = .tags

    /// Notes grouped by tag, sorted by tag frequency descending.
    var notesByTag: [(tag: String, notes: [NoteRecord])] {
        var groups: [String: [NoteRecord]] = [:]
        for note in notes {
            for tag in note.tags {
                groups[tag, default: []].append(note)
            }
        }
        let untagged = notes.filter(\.tags.isEmpty)
        var result = groups.sorted { $0.value.count > $1.value.count }
            .map { (tag: $0.key, notes: $0.value) }
        if !untagged.isEmpty {
            result.append((tag: "Untagged", notes: untagged))
        }
        return result
    }

    /// Notes grouped by time period (Today, Yesterday, This Week, This Month, Older).
    var notesByTimePeriod: [(period: String, notes: [NoteRecord])] {
        let calendar = Calendar.current
        var today: [NoteRecord] = [], yesterday: [NoteRecord] = []
        var thisWeek: [NoteRecord] = [], thisMonth: [NoteRecord] = []
        var older: [NoteRecord] = []
        for note in notes {
            if calendar.isDateInToday(note.updatedAt) {
                today.append(note)
            } else if calendar.isDateInYesterday(note.updatedAt) {
                yesterday.append(note)
            } else if calendar.isDate(note.updatedAt, equalTo: Date(), toGranularity: .weekOfYear) {
                thisWeek.append(note)
            } else if calendar.isDate(note.updatedAt, equalTo: Date(), toGranularity: .month) {
                thisMonth.append(note)
            } else {
                older.append(note)
            }
        }
        return [("Today", today), ("Yesterday", yesterday),
                ("This Week", thisWeek), ("This Month", thisMonth),
                ("Older", older)].filter { !$0.1.isEmpty }
    }

    /// All unique tags across all notes, sorted by frequency descending.
    var allTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for note in notes {
            for tag in note.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map { (tag: $0.key, count: $0.value) }
    }

    /// JSON-serialized graph data for the D3.js knowledge graph visualization.
    /// Recomputed from `notes` + `backlinkIndex` when accessed.
    var knowledgeGraphJSON: String {
        let data = KnowledgeGraphData.build(from: notes, backlinkIndex: backlinkIndex)
        do {
            let jsonData = try JSONEncoder().encode(data)
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            logger.error("Failed to encode knowledge graph: \(error)")
            return "{}"
        }
    }

    /// Notes filtered by the active tag filter. Returns all notes when no filter is set.
    var filteredNotes: [NoteRecord] {
        guard let tag = selectedTagFilter else { return notes }
        return notes.filter { $0.tags.contains(tag) }
    }

    /// Backlink entries for the currently selected note (notes that reference it).
    var selectedNoteBacklinks: [(id: NoteID, title: String)] {
        guard let title = selectedNote?.title else { return [] }
        return backlinkIndex.backlinks(for: title)
    }

    /// Files in knowledge/sources/ grouped by subdirectory.
    var sourceEntries: [KnowledgeFileEntry] {
        guard let dir = sourcesDirectoryURL else { return [] }
        return KnowledgeFileLister.listSources(in: dir)
    }

    /// Files in knowledge/log/ grouped by date directory.
    var logEntries: [KnowledgeFileEntry] {
        guard let dir = logDirectoryURL else { return [] }
        return KnowledgeFileLister.listLogs(in: dir)
    }

    /// Sibling directory of notesDirectoryURL for sources.
    private var sourcesDirectoryURL: URL? {
        notesDirectoryURL?.deletingLastPathComponent().appendingPathComponent("sources")
    }

    /// Sibling directory of notesDirectoryURL for log.
    private var logDirectoryURL: URL? {
        notesDirectoryURL?.deletingLastPathComponent().appendingPathComponent("log")
    }

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
    /// Handles both flat notes (match by lastPathComponent) and folder notes (match by relative path).
    func findNote(byFileURL url: URL) async -> NoteRecord? {
        if notes.isEmpty {
            await loadNotes()
        }
        return notes.first { note in
            NoteFileService.filename(for: note) == relativeNotePath(for: url)
        }
    }

    /// Returns the file path relative to `notesDirectoryURL` for matching against `NoteFileService.filename`.
    /// For folder notes this yields `slug/README.md`; for flat notes just the filename.
    private func relativeNotePath(for url: URL) -> String {
        guard let dir = notesDirectoryURL else { return url.lastPathComponent }
        let base = dir.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full.hasPrefix(base) {
            let rel = String(full.dropFirst(base.count))
            return rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        }
        return url.lastPathComponent
    }

    /// Find a note by title (case-insensitive). Used for backlink navigation.
    func findNote(byTitle title: String) -> NoteRecord? {
        notes.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    /// Navigate to a note referenced by a `[[backlink]]`. No-op if title not found.
    func navigateToBacklink(title: String) {
        guard let note = findNote(byTitle: title) else {
            logger.info("Backlink target not found: \(title)")
            return
        }
        selectNote(id: note.id)
    }

    func loadNotes() async {
        do {
            notes = try await repository.fetchAll()
            backlinkIndex.rebuild(from: notes)
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
