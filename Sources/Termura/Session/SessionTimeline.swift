import DequeModule
import Foundation

/// A single command execution entry in the session timeline.
struct TimelineTurn: Identifiable, Sendable {
    let id: UUID
    let chunkID: UUID
    let command: String
    let startedAt: Date
    let exitCode: Int?
    /// Wall-clock duration of the command; nil if the chunk finished time was not recorded.
    let duration: TimeInterval?
    /// Semantic classification of the output block (commandOutput, toolCall, diff, etc.).
    let contentType: OutputContentType
    /// Scrollback depth (totalLines - visibleRows) captured at append time.
    /// Used by Activity click-to-scroll to restore the terminal view position.
    let startLine: Int?
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
@Observable
@MainActor
final class SessionTimeline {
    private(set) var turns: Deque<TimelineTurn> = []

    func append(_ chunk: OutputChunk, startLine: Int? = nil) {
        let duration = chunk.finishedAt.map { $0.timeIntervalSince(chunk.startedAt) }
        let turn = TimelineTurn(
            id: UUID(),
            chunkID: chunk.id,
            command: chunk.commandText,
            startedAt: chunk.startedAt,
            exitCode: chunk.exitCode,
            duration: duration,
            contentType: chunk.contentType,
            startLine: startLine
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
