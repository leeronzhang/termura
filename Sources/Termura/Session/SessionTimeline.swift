import Foundation

/// A single command execution entry in the session timeline.
struct TimelineTurn: Identifiable, Sendable {
    let id: UUID
    let chunkID: UUID
    let command: String
    let startedAt: Date
    let exitCode: Int?
    var branchPoints: [BranchPointMarker] = []
}

/// Marks the point where a branch was created from a timeline turn.
struct BranchPointMarker: Identifiable, Sendable {
    let id = UUID()
    let branchID: SessionID
    let branchType: BranchType
    let createdAt: Date
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

    func addBranchMarker(at turnIndex: Int, marker: BranchPointMarker) {
        guard turns.indices.contains(turnIndex) else { return }
        turns[turnIndex].branchPoints.append(marker)
    }

    func clear() {
        turns.removeAll()
    }
}
