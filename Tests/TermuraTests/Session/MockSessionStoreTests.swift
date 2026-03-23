import XCTest
@testable import Termura

@MainActor
final class MockSessionStoreTests: XCTestCase {

    func testIsRestoredSessionAlwaysFalse() {
        let mock = MockSessionStore()
        let session = mock.createSession(title: "Test")
        XCTAssertFalse(mock.isRestoredSession(id: session.id))
        XCTAssertFalse(mock.isRestoredSession(id: SessionID()))
    }
}
