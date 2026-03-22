import Foundation
import Testing
@testable import Termura

@Suite("TimelineBranchMarker")
struct TimelineBranchMarkerTests {

    private func makeTurn() -> TimelineTurn {
        TimelineTurn(
            id: .init(),
            chunkID: .init(),
            command: "echo test",
            startedAt: Date(),
            exitCode: 0
        )
    }

    @Test @MainActor func defaultBranchPointsEmpty() {
        let turn = makeTurn()
        #expect(turn.branchPoints.isEmpty)
    }

    @Test @MainActor func addBranchMarkerAtValidIndex() async {
        let timeline = SessionTimeline()
        let chunk = OutputChunk(
            sessionID: SessionID(),
            commandText: "ls",
            outputLines: [],
            rawANSI: "",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: nil
        )
        timeline.append(chunk)

        let marker = BranchPointMarker(
            branchID: SessionID(),
            branchType: .investigation,
            createdAt: Date()
        )
        timeline.addBranchMarker(at: 0, marker: marker)

        #expect(timeline.turns[0].branchPoints.count == 1)
        #expect(timeline.turns[0].branchPoints[0].branchType == .investigation)
    }

    @Test @MainActor func addBranchMarkerOutOfBoundsDoesNotCrash() async {
        let timeline = SessionTimeline()
        let marker = BranchPointMarker(
            branchID: SessionID(),
            branchType: .fix,
            createdAt: Date()
        )
        // Should not crash — no turns exist.
        timeline.addBranchMarker(at: 5, marker: marker)
        #expect(timeline.turns.isEmpty)
    }

    @Test @MainActor func multipleMarkersAccumulate() async {
        let timeline = SessionTimeline()
        let chunk = OutputChunk(
            sessionID: SessionID(),
            commandText: "ls",
            outputLines: [],
            rawANSI: "",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: nil
        )
        timeline.append(chunk)

        let m1 = BranchPointMarker(branchID: SessionID(), branchType: .investigation, createdAt: Date())
        let m2 = BranchPointMarker(branchID: SessionID(), branchType: .review, createdAt: Date())
        timeline.addBranchMarker(at: 0, marker: m1)
        timeline.addBranchMarker(at: 0, marker: m2)

        #expect(timeline.turns[0].branchPoints.count == 2)
    }
}
