import XCTest
@testable import Termura

@MainActor
final class TerminalEngineStoreTests: XCTestCase {
    private var mockEngine: MockTerminalEngine!
    private var factory: MockTerminalEngineFactory!
    private var store: TerminalEngineStore!

    override func setUp() async throws {
        mockEngine = MockTerminalEngine()
        factory = MockTerminalEngineFactory(engine: mockEngine)
        store = TerminalEngineStore(factory: factory)
    }

    func testCreateEngineReturnsEngine() {
        let id = SessionID()
        let engine = store.createEngine(for: id, shell: "/bin/zsh")
        XCTAssertNotNil(engine)
    }

    func testEngineForIDReturnsSameInstance() {
        let id = SessionID()
        store.createEngine(for: id, shell: "/bin/zsh")
        let retrieved = store.engine(for: id)
        XCTAssertTrue(retrieved === mockEngine)
    }

    func testEngineForUnknownIDReturnsNil() {
        let unknown = SessionID()
        XCTAssertNil(store.engine(for: unknown))
    }

    func testTerminateEngineRemovesFromStore() async {
        let id = SessionID()
        store.createEngine(for: id, shell: "/bin/zsh")
        store.terminateEngine(for: id)
        // Allow async terminate Task to run
        await Task.yield()
        XCTAssertNil(store.engine(for: id))
    }

    func testTerminateAllClearsAllEngines() async {
        let id1 = SessionID()
        let id2 = SessionID()
        // Use separate factories for distinct engines
        let e2 = MockTerminalEngine()
        let factory2 = MockTerminalEngineFactory(engine: e2)
        let store2 = TerminalEngineStore(factory: factory2)
        store2.createEngine(for: id1, shell: "/bin/zsh")
        store2.createEngine(for: id2, shell: "/bin/zsh")
        store2.terminateAll()
        await Task.yield()
        XCTAssertNil(store2.engine(for: id1))
        XCTAssertNil(store2.engine(for: id2))
    }
}
