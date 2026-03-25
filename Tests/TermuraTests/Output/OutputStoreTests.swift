import XCTest
@testable import Termura

@MainActor
final class OutputStoreTests: XCTestCase {
    private let sessionID = SessionID()

    private func makeChunk(command: String = "echo test") -> OutputChunk {
        OutputChunk(
            sessionID: sessionID,
            commandText: command,
            outputLines: ["output"],
            rawANSI: "output",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )
    }

    // MARK: - Append

    func testAppendAddsChunk() {
        let store = OutputStore(sessionID: sessionID, capacity: 10)
        store.append(makeChunk())
        XCTAssertEqual(store.chunks.count, 1)
    }

    func testAppendEvictsOldestAtCapacity() {
        let store = OutputStore(sessionID: sessionID, capacity: 2)
        store.append(makeChunk(command: "first"))
        store.append(makeChunk(command: "second"))
        store.append(makeChunk(command: "third"))

        XCTAssertEqual(store.chunks.count, 2)
        XCTAssertEqual(store.chunks[0].commandText, "second")
        XCTAssertEqual(store.chunks[1].commandText, "third")
    }

    func testAppendPostsNotification() {
        let store = OutputStore(sessionID: sessionID, capacity: 10)
        let expectation = expectation(forNotification: .chunkCompleted, object: nil)
        store.append(makeChunk())
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Toggle collapse

    func testToggleCollapseFlipsState() {
        let store = OutputStore(sessionID: sessionID, capacity: 10)
        let chunk = makeChunk()
        store.append(chunk)

        XCTAssertFalse(store.chunks[0].isCollapsed)
        store.toggleCollapse(id: chunk.id)
        XCTAssertTrue(store.chunks[0].isCollapsed)
        store.toggleCollapse(id: chunk.id)
        XCTAssertFalse(store.chunks[0].isCollapsed)
    }

    func testToggleCollapseNonexistentIDIsNoop() {
        let store = OutputStore(sessionID: sessionID, capacity: 10)
        store.append(makeChunk())
        // Should not crash.
        store.toggleCollapse(id: UUID())
        XCTAssertEqual(store.chunks.count, 1)
    }

    // MARK: - Clear

    func testClearRemovesAll() {
        let store = OutputStore(sessionID: sessionID, capacity: 10)
        store.append(makeChunk())
        store.append(makeChunk())
        store.append(makeChunk())
        store.clear()
        XCTAssertTrue(store.chunks.isEmpty)
    }
}
