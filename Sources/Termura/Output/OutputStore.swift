import DequeModule
import Foundation

/// Observable store of output chunks for a single session.
/// Maintains a sliding window of the most recent `capacity` chunks.
@MainActor
final class OutputStore: ObservableObject {
    // MARK: - Published state

    @Published private(set) var chunks: Deque<OutputChunk> = []

    // MARK: - Configuration

    let sessionID: SessionID
    private let capacity: Int
    private weak var commandRouter: CommandRouter?

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

    /// Toggle the collapsed state of a chunk by ID.
    func toggleCollapse(id: UUID) {
        guard let index = chunks.firstIndex(where: { $0.id == id }) else { return }
        chunks[index].isCollapsed.toggle()
    }

    /// Remove all chunks.
    func clear() {
        chunks.removeAll()
    }
}
