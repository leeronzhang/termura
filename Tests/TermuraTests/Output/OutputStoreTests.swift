import Foundation
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

    func testAppendNotifiesCommandRouter() {
        let router = CommandRouter()
        let store = OutputStore(sessionID: sessionID, capacity: 10, commandRouter: router)
        var received = false
        router.onChunkCompleted { _ in received = true }
        store.append(makeChunk())
        XCTAssertTrue(received)
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

    // MARK: - Capacity Edge Cases

    func testAppendExactlyAtCapacityNoEviction() {
        let store = OutputStore(sessionID: sessionID, capacity: 3)
        store.append(makeChunk(command: "a"))
        store.append(makeChunk(command: "b"))
        store.append(makeChunk(command: "c"))
        XCTAssertEqual(store.chunks.count, 3)
        XCTAssertEqual(store.chunks[0].commandText, "a")
    }

    func testAppendDoubleCapacityKeepsOrder() {
        let store = OutputStore(sessionID: sessionID, capacity: 3)
        for idx in 0 ..< 6 {
            store.append(makeChunk(command: "cmd\(idx)"))
        }
        XCTAssertEqual(store.chunks.count, 3)
        XCTAssertEqual(store.chunks[0].commandText, "cmd3")
        XCTAssertEqual(store.chunks[1].commandText, "cmd4")
        XCTAssertEqual(store.chunks[2].commandText, "cmd5")
    }

    func testClearThenAppendWorks() {
        let store = OutputStore(sessionID: sessionID, capacity: 5)
        store.append(makeChunk(command: "before"))
        store.clear()
        store.append(makeChunk(command: "after"))
        XCTAssertEqual(store.chunks.count, 1)
        XCTAssertEqual(store.chunks[0].commandText, "after")
    }
}
