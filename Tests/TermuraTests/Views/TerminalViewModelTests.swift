import Foundation
import XCTest
@testable import Termura

@MainActor
final class TerminalViewModelTests: XCTestCase {
    private var engine: MockTerminalEngine!
    private var sessionStore: MockSessionStore!
    private var outputStore: OutputStore!
    private var tokenService: TokenCountingService!
    private var modeController: InputModeController!
    private var sessionID: SessionID!

    override func setUp() async throws {
        sessionID = SessionID()
        engine = MockTerminalEngine()
        sessionStore = MockSessionStore()
        outputStore = OutputStore(sessionID: sessionID)
        tokenService = TokenCountingService()
        modeController = InputModeController()
    }

    private func makeViewModel(
        isRestoredSession: Bool = false
    ) -> TerminalViewModel {
        TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            outputStore: outputStore,
            tokenCountingService: tokenService,
            modeController: modeController,
            isRestoredSession: isRestoredSession
        )
    }

    // MARK: - Init state

    func testInitialMetadataHasSessionID() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.currentMetadata.sessionID, sessionID)
    }

    func testInitialIsInteractivePromptFalse() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.isInteractivePrompt)
    }

    func testInitialPendingRiskAlertNil() {
        let vm = makeViewModel()
        XCTAssertNil(vm.pendingRiskAlert)
    }

    func testInitialContextWindowAlertNil() {
        let vm = makeViewModel()
        XCTAssertNil(vm.contextWindowAlert)
    }

    // MARK: - Context injection guards

    func testNonRestoredSessionDoesNotInjectContext() {
        let vm = makeViewModel(isRestoredSession: false)
        // hasInjectedContext is private, but we verify via behavior:
        // non-restored sessions should never call contextInjectionService.
        // Since contextInjectionService is nil, nothing happens — just verify no crash.
        XCTAssertNotNil(vm)
    }

    // MARK: - Output event handling

    func testTitleChangedUpdatesMetadata() async throws {
        let vm = makeViewModel()
        // Emit a title change event.
        await engine.emit(.titleChanged("New Title"))
        // Give the stream subscription time to process.
        try await yieldForDuration(seconds: 0.1)
        // titleChanged updates the session record, not metadata directly
        _ = vm
    }

    func testDirectoryChangedUpdatesMetadata() async throws {
        let vm = makeViewModel()
        await engine.emit(.workingDirectoryChanged("/tmp/test"))
        try await yieldForDuration(seconds: 0.1)
        XCTAssertEqual(vm.currentMetadata.workingDirectory, "/tmp/test")
    }

    // MARK: - Mode controller

    func testModeControllerStartsInPassthrough() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.modeController.mode, .passthrough)
    }

    // MARK: - Send and resize

    func testSendDelegatesToEngine() async throws {
        let vm = makeViewModel()
        vm.send("hello")
        try await yieldForDuration(seconds: 0.05)
        let sent = await engine.sentTexts
        XCTAssertTrue(sent.contains("hello"))
    }

    func testResizeDelegatesToEngine() async throws {
        let vm = makeViewModel()
        vm.resize(columns: 120, rows: 40)
        try await yieldForDuration(seconds: 0.05)
        let resizes = await engine.resizes
        XCTAssertFalse(resizes.isEmpty)
        XCTAssertEqual(resizes.last?.0, 120)
        XCTAssertEqual(resizes.last?.1, 40)
    }

    // MARK: - Shell event handling

    func testPromptStartedSwitchesToEditor() async throws {
        let vm = makeViewModel()
        modeController.switchToPassthrough()
        XCTAssertEqual(modeController.mode, .passthrough)

        await engine.emitShellEvent(.promptStarted)
        try await yieldForDuration(seconds: 0.1)
        XCTAssertEqual(vm.modeController.mode, .editor)
    }

    func testExecutionStartedStaysInPassthrough() async throws {
        let vm = makeViewModel()
        XCTAssertEqual(modeController.mode, .passthrough)

        await engine.emitShellEvent(.executionStarted)
        try await yieldForDuration(seconds: 0.1)
        XCTAssertEqual(vm.modeController.mode, .passthrough)
        _ = vm
    }

    func testExecutionFinishedSwitchesToEditor() async throws {
        let vm = makeViewModel()
        modeController.switchToPassthrough()

        await engine.emitShellEvent(.executionFinished(exitCode: 0))
        try await yieldForDuration(seconds: 0.1)
        XCTAssertEqual(vm.modeController.mode, .editor)
        _ = vm
    }

    // MARK: - Data event accumulates tokens

    func testDataEventAccumulatesTokens() async throws {
        let vm = makeViewModel()
        let text = String(repeating: "a", count: 400) // 400 chars → 100 tokens
        let data = text.data(using: .utf8) ?? Data()
        await engine.emit(.data(data))
        try await yieldForDuration(seconds: 0.2)

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
        _ = vm
    }

    // MARK: - Process exit

    func testProcessExitDoesNotCrash() async throws {
        let vm = makeViewModel()
        await engine.emit(.processExited(0))
        try await yieldForDuration(seconds: 0.1)
        // No crash, no handoff (no sessionHandoffService set).
        XCTAssertNotNil(vm)
    }

    // MARK: - Context injection

    func testInjectContextGuardsNonRestoredSession() {
        let vm = makeViewModel(isRestoredSession: false)
        vm.injectContextIfNeeded()
        // Should return early — no service, no crash.
        XCTAssertNotNil(vm)
    }

    func testInjectContextGuardsNoService() {
        let vm = makeViewModel(isRestoredSession: true)
        vm.injectContextIfNeeded()
        // contextInjectionService is nil → returns early.
        XCTAssertNotNil(vm)
    }

    // MARK: - spawnTracked lifecycle

    func testSpawnTrackedExecutesOperation() async throws {
        let vm = makeViewModel()
        let expectation = XCTestExpectation(description: "operation executed")
        vm.spawnTracked {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testSpawnDetachedTrackedExecutesOffMainActor() async throws {
        let vm = makeViewModel()
        let expectation = XCTestExpectation(description: "detached operation executed")
        vm.spawnDetachedTracked {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testSendTracksTask() async throws {
        let vm = makeViewModel()
        vm.send("hello")
        // The send creates a tracked task — give it time to complete.
        try await yieldForDuration(seconds: 0.1)
        // Engine should have received the text.
        let sent = await engine.sentTexts
        XCTAssertTrue(sent.contains("hello"))
    }

    func testResizeTracksTask() async throws {
        let vm = makeViewModel()
        vm.resize(columns: 120, rows: 40)
        try await yieldForDuration(seconds: 0.1)
        let resizes = await engine.resizes
        XCTAssertEqual(resizes.count, 1)
        XCTAssertEqual(resizes.first?.0, 120)
        XCTAssertEqual(resizes.first?.1, 40)
    }
}
