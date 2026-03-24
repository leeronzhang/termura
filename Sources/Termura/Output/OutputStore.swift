import Foundation

/// Observable store of output chunks for a single session.
/// Maintains a sliding window of the most recent `capacity` chunks.
@MainActor
final class OutputStore: ObservableObject {
    // MARK: - Published state

    @Published private(set) var chunks: [OutputChunk] = []

    // MARK: - Configuration

    let sessionID: SessionID
    private let capacity: Int

    // MARK: - Init

    init(sessionID: SessionID, capacity: Int = AppConfig.Output.maxChunksPerSession) {
        self.sessionID = sessionID
        self.capacity = capacity
    }

    // MARK: - Mutations

    /// Append a new chunk, evicting the oldest if at capacity.
    /// Posts `.chunkCompleted` notification so AppDelegate can trigger background services.
    func append(_ chunk: OutputChunk) {
        if chunks.count >= capacity {
            chunks.removeFirst()
        }
        chunks.append(chunk)
        NotificationCenter.default.post(name: .chunkCompleted, object: chunk)
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

extension Notification.Name {
    static let chunkCompleted = Notification.Name("com.termura.chunkCompleted")
}
