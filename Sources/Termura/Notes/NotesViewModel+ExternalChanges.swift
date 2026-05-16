import Foundation
import OSLog

private let externalChangeLogger = Logger(
    subsystem: "com.termura.app",
    category: "NotesViewModel+ExternalChanges"
)

extension NotesViewModel {
    /// Re-fetches notes from the repository and rebuilds the backlink index.
    /// Used after the repository signals an external change (file-system watcher).
    /// Preserves in-memory selection state and editing buffers.
    func reloadFromRepository() async {
        do {
            let fetched = try await repository.fetchAll()
            notes = fetched
            backlinkIndex.rebuild(from: notes)
            if errorMessage != nil { errorMessage = nil }
        } catch {
            errorMessage = "Failed to refresh notes: \(error.localizedDescription)"
            externalChangeLogger.error(
                "Failed to reload notes after external change: \(error.localizedDescription)"
            )
        }
    }

    /// Spins up the long-lived drain task that re-fetches notes whenever the
    /// repository's watcher reports an external sync. Idempotent — second call
    /// is a no-op while an existing drain is alive.
    func startExternalChangeWatchIfNeeded() {
        guard externalChangeWatchTask == nil else { return }
        let stream = repository.externalChanges()
        externalChangeWatchTask = Task { [weak self] in
            await self?.drainExternalChanges(stream)
        }
    }

    private func drainExternalChanges(_ stream: AsyncStream<Void>) async {
        for await _ in stream {
            if Task.isCancelled { break }
            await reloadFromRepository()
        }
        // Stream finished (repository.stopWatching() called) → clear the slot
        // so a subsequent loadNotes() can restart the drain.
        externalChangeWatchTask = nil
    }
}
