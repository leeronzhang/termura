@testable import Termura
import XCTest

@MainActor
final class SessionStoreRestoredTests: XCTestCase {
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

    func testNewSessionIsNotRestored() {
        let session = store.createSession(title: "New")
        XCTAssertFalse(store.isRestoredSession(id: session.id))
    }

    func testRestoredSessionIDsEmptyByDefault() {
        XCTAssertTrue(store.restoredSessionIDs.isEmpty)
    }

    func testNonExistentSessionIsNotRestored() {
        let phantom = SessionID()
        XCTAssertFalse(store.isRestoredSession(id: phantom))
    }
}
