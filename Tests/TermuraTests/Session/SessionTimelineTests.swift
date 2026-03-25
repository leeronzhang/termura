import XCTest
@testable import Termura

@MainActor
final class SessionTimelineTests: XCTestCase {
    private let sessionID = SessionID()

    private func makeChunk(command: String = "ls", exitCode: Int? = 0) -> OutputChunk {
        OutputChunk(
            sessionID: sessionID,
            commandText: command,
            outputLines: ["output"],
            rawANSI: "output",
            exitCode: exitCode,
            startedAt: Date(),
            finishedAt: Date()
        )
    }

    // MARK: - Append

    func testAppendAddsTurn() {
        let timeline = SessionTimeline()
        timeline.append(makeChunk())
        XCTAssertEqual(timeline.turns.count, 1)
        XCTAssertEqual(timeline.turns.first?.command, "ls")
    }

    func testAppendEvictsAtMaxTurns() {
        let timeline = SessionTimeline()
        let max = AppConfig.Timeline.maxTurns
        for i in 0 ..< max + 5 {
            timeline.append(makeChunk(command: "cmd\(i)"))
        }
        XCTAssertEqual(timeline.turns.count, max)
        // First turn should be "cmd5" (oldest 5 evicted)
        XCTAssertEqual(timeline.turns.first?.command, "cmd5")
    }

    // MARK: - Branch markers

    func testAddBranchMarkerAtValidIndex() {
        let timeline = SessionTimeline()
        timeline.append(makeChunk())
        let marker = BranchPointMarker(
            branchID: SessionID(),
            branchType: .investigation,
            createdAt: Date()
        )
        timeline.addBranchMarker(at: 0, marker: marker)
        XCTAssertEqual(timeline.turns[0].branchPoints.count, 1)
        XCTAssertEqual(timeline.turns[0].branchPoints.first?.branchType, .investigation)
    }

    func testAddBranchMarkerAtInvalidIndexIsNoop() {
        let timeline = SessionTimeline()
        timeline.append(makeChunk())
        let marker = BranchPointMarker(
            branchID: SessionID(),
            branchType: .fix,
            createdAt: Date()
        )
        // Should not crash.
        timeline.addBranchMarker(at: 999, marker: marker)
        XCTAssertTrue(timeline.turns[0].branchPoints.isEmpty)
    }

    // MARK: - Clear

    func testClearRemovesAllTurns() {
        let timeline = SessionTimeline()
        timeline.append(makeChunk())
        timeline.append(makeChunk())
        timeline.clear()
        XCTAssertTrue(timeline.turns.isEmpty)
    }
}
