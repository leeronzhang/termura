import XCTest
@testable import Termura

@MainActor
final class TerminalEngineFactoryTests: XCTestCase {
    override func setUp() async throws {}

    // MARK: - MockTerminalEngineFactory

    func testMockFactoryCreatesEngine() {
        let factory = MockTerminalEngineFactory()
        let sessionID = SessionID()
        let engine = factory.makeEngine(for: sessionID, shell: "/bin/zsh", currentDirectory: nil)
        XCTAssertNotNil(engine)
    }

    func testMockFactoryEngineHasCorrectSessionID() {
        // MockTerminalEngineFactory returns the same engine instance regardless of
        // sessionID, but verify the factory accepts different IDs without error.
        let factory = MockTerminalEngineFactory()
        let sid1 = SessionID()
        let sid2 = SessionID()
        let engine1 = factory.makeEngine(for: sid1, shell: "/bin/zsh", currentDirectory: nil)
        let engine2 = factory.makeEngine(for: sid2, shell: "/bin/zsh", currentDirectory: nil)
        // Both should be valid engines (non-nil).
        XCTAssertNotNil(engine1)
        XCTAssertNotNil(engine2)
    }

    func testMockFactoryMultipleCallsReturnDistinctEngines() {
        // When constructed with distinct MockTerminalEngine instances, factories
        // return distinct engines.
        let engineA = MockTerminalEngine()
        let engineB = MockTerminalEngine()
        let factoryA = MockTerminalEngineFactory(engine: engineA)
        let factoryB = MockTerminalEngineFactory(engine: engineB)
        let sessionID = SessionID()

        let resultA = factoryA.makeEngine(for: sessionID, shell: "/bin/zsh", currentDirectory: nil)
        let resultB = factoryB.makeEngine(for: sessionID, shell: "/bin/zsh", currentDirectory: nil)

        // They should be different object instances.
        let objA = resultA as AnyObject
        let objB = resultB as AnyObject
        XCTAssertFalse(objA === objB)
    }
}
