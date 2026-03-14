import Foundation

/// A single command execution entry in the session timeline.
struct TimelineTurn: Identifiable, Sendable {
    let id: UUID
    let chunkID: UUID
    let command: String
    let startedAt: Date
    let exitCode: Int?
}

/// Maintains an ordered list of timeline turns driven by OutputChunk arrivals.
/// Bound to an OutputStore and updated as chunks are appended.
@MainActor
final class SessionTimeline: ObservableObject {
    @Published private(set) var turns: [TimelineTurn] = []

    func append(_ chunk: OutputChunk) {
        let turn = TimelineTurn(
            id: UUID(),
            chunkID: chunk.id,
            command: chunk.commandText,
            startedAt: chunk.startedAt,
            exitCode: chunk.exitCode
        )
        turns.append(turn)
        if turns.count > AppConfig.Timeline.maxTurns {
            turns.removeFirst()
        }
    }

    func clear() {
        turns.removeAll()
    }
}
