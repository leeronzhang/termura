import DequeModule
import Foundation
import Observation

/// Observable store of output chunks for a single session.
/// Maintains a sliding window of the most recent `capacity` chunks.
///
/// Uses `@Observable` (not `ObservableObject`) so SwiftUI views that access
/// `chunks` via a plain property path (e.g. `state.outputStore.chunks`) register
/// a fine-grained dependency directly on this instance — no nested-ObservableObject
/// observation-chain breakage. (CLAUDE.md Principle 9)
@Observable
@MainActor
final class OutputStore {
    // MARK: - Observable state

    private(set) var chunks: Deque<OutputChunk> = []

    // MARK: - Configuration

    let sessionID: SessionID
    private let capacity: Int
    // Strong reference: OutputStore and CommandRouter are both owned by
    // SessionViewStateManager — no retain cycle exists; weak would risk silent drops.
    private let commandRouter: CommandRouter?

    // MARK: - Init

    init(
        sessionID: SessionID,
        capacity: Int = AppConfig.Output.maxChunksPerSession,
        commandRouter: CommandRouter? = nil
    ) {
        self.sessionID = sessionID
        self.capacity = capacity
        self.commandRouter = commandRouter
    }

    // MARK: - Mutations

    /// Append a new chunk, evicting the oldest if at capacity.
    /// Notifies registered CommandRouter handlers for background services.
    func append(_ chunk: OutputChunk) {
        if chunks.count >= capacity {
            chunks.removeFirst()
        }
        chunks.append(chunk)
        commandRouter?.notifyChunkCompleted(chunk)
    }

    /// Remove all chunks.
    func clear() {
        chunks.removeAll()
    }

    /// Toggle the collapsed state of a chunk by ID.
    func toggleCollapse(id: UUID) {
        guard let index = chunks.firstIndex(where: { $0.id == id }) else { return }
        chunks[index].isCollapsed.toggle()
    }
}
