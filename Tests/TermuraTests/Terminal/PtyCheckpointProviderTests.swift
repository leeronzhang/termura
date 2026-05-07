@testable import Termura
import TermuraRemoteProtocol
import XCTest

@MainActor
final class PtyCheckpointProviderTests: XCTestCase {
    func testProducesCheckpointFromStyledSnapshotWhenAvailable() throws {
        let engine = DebugTerminalEngine()
        engine.stubbedScreen = TerminalScreenSnapshot(
            rows: 2,
            cols: 4,
            lines: ["abcd", "efgh"]
        )
        engine.stubbedStyledScreen = TerminalStyledScreenSnapshot(
            rows: 2,
            cols: 4,
            lines: ["abcd", "efgh"],
            styledLines: [
                StyledLine(runs: [StyledRun(text: "abcd", style: .default)]),
                StyledLine(runs: [StyledRun(text: "efgh", style: .default)])
            ]
        )
        let sessionId = UUID()
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        let cp = try XCTUnwrap(
            PtyCheckpointProvider.makeCheckpoint(
                engine: engine,
                sessionId: sessionId,
                seq: 7,
                producedAt: frozen
            )
        )
        XCTAssertEqual(cp.sessionId, sessionId)
        XCTAssertEqual(cp.seq, 7)
        XCTAssertEqual(cp.rows, 2)
        XCTAssertEqual(cp.cols, 4)
        XCTAssertEqual(cp.lines, ["abcd", "efgh"])
        XCTAssertNotNil(cp.styledLines)
        XCTAssertEqual(cp.producedAt, frozen)
    }

    func testFallsBackToPlainSnapshotWhenStyledMissing() throws {
        let engine = DebugTerminalEngine()
        engine.stubbedScreen = TerminalScreenSnapshot(
            rows: 1,
            cols: 5,
            lines: ["plain"]
        )
        // stubbedStyledScreen left nil ⇒ falls back to plain path.
        let cp = try XCTUnwrap(
            PtyCheckpointProvider.makeCheckpoint(
                engine: engine,
                sessionId: UUID(),
                seq: 0
            )
        )
        XCTAssertEqual(cp.rows, 1)
        XCTAssertEqual(cp.cols, 5)
        XCTAssertEqual(cp.lines, ["plain"])
        XCTAssertNil(cp.styledLines, "Plain fallback must not synthesize styledLines")
    }

    func testReturnsNilWhenEngineHasNoSurface() {
        let engine = DebugTerminalEngine()
        // Both stubs nil ⇒ no live surface; provider returns nil so the
        // router pump skips the keyframe and retries on next cadence tick.
        let cp = PtyCheckpointProvider.makeCheckpoint(
            engine: engine,
            sessionId: UUID(),
            seq: 0
        )
        XCTAssertNil(cp)
    }

    func testFallsBackWhenStyledLinesEmpty() throws {
        // Empty styledLines should match production behaviour in
        // captureRemoteScreen (`!styled.lines.isEmpty`). Provider must
        // prefer the plain snapshot when styled is empty.
        let engine = DebugTerminalEngine()
        engine.stubbedScreen = TerminalScreenSnapshot(
            rows: 1,
            cols: 3,
            lines: ["abc"]
        )
        engine.stubbedStyledScreen = TerminalStyledScreenSnapshot(
            rows: 0,
            cols: 0,
            lines: [],
            styledLines: []
        )
        let cp = try XCTUnwrap(
            PtyCheckpointProvider.makeCheckpoint(
                engine: engine,
                sessionId: UUID(),
                seq: 1
            )
        )
        XCTAssertEqual(cp.lines, ["abc"])
        XCTAssertNil(cp.styledLines)
    }

    func testCheckpointSeqMatchesCallerSpecified() throws {
        // Caller (router pump) owns the seq counter; provider must echo
        // it verbatim so the keyframe slots into the chunk sequence
        // without gap or overlap.
        let engine = DebugTerminalEngine()
        engine.stubbedScreen = TerminalScreenSnapshot(rows: 1, cols: 1, lines: ["x"])
        let cp1 = try XCTUnwrap(
            PtyCheckpointProvider.makeCheckpoint(engine: engine, sessionId: UUID(), seq: 0)
        )
        let cp2 = try XCTUnwrap(
            PtyCheckpointProvider.makeCheckpoint(engine: engine, sessionId: UUID(), seq: UInt64.max)
        )
        XCTAssertEqual(cp1.seq, 0)
        XCTAssertEqual(cp2.seq, .max)
    }
}
