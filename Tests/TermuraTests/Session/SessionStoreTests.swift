@testable import Termura
import XCTest

@MainActor
final class SessionStoreTests: XCTestCase {
    private var engineFactory: MockTerminalEngineFactory!
    private var engineStore: TerminalEngineStore!
    private var store: SessionStore!

    override func setUp() async throws {
        engineFactory = MockTerminalEngineFactory()
        engineStore = TerminalEngineStore(factory: engineFactory)
        store = SessionStore(engineStore: engineStore, repository: MockSessionRepository())
    }

    override func tearDown() async throws {
        await engineStore.terminateAll()
    }

    func testCreateSessionAddsToList() {
        let session = store.createSession(title: "Test")
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.title, "Test")
        XCTAssertEqual(store.activeSessionID, session.id)
    }

    func testDeleteSessionRemovesFromList() async {
        let session = store.createSession(title: "Test")
        await store.deleteSession(id: session.id)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.activeSessionID)
    }

    func testActivateSessionUpdatesActiveID() {
        let first = store.createSession(title: "First")
        let second = store.createSession(title: "Second")
        store.activateSession(id: first.id)
        XCTAssertEqual(store.activeSessionID, first.id)
        store.activateSession(id: second.id)
        XCTAssertEqual(store.activeSessionID, second.id)
    }

    func testRenameSessionUpdatesTitle() {
        let session = store.createSession(title: "Old")
        store.renameSession(id: session.id, title: "New")
        XCTAssertEqual(store.sessions.first?.title, "New")
    }

    func testDeleteActiveSessionFallsBackToLast() async {
        let first = store.createSession(title: "First")
        let second = store.createSession(title: "Second")
        store.activateSession(id: second.id)
        await store.deleteSession(id: second.id)
        XCTAssertEqual(store.activeSessionID, first.id)
    }

    func testActivateNonExistentSessionIsNoop() {
        let phantom = SessionID()
        store.activateSession(id: phantom)
        XCTAssertNil(store.activeSessionID)
    }

    func testMultipleSessionsOrderedByCreation() {
        for i in 1 ... 5 {
            store.createSession(title: "Session \(i)")
        }
        XCTAssertEqual(store.sessions.count, 5)
        XCTAssertEqual(store.sessions.last?.title, "Session 5")
    }
}
