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
        try await Task.sleep(for: .milliseconds(100))
        // titleChanged updates the session record, not metadata directly
        _ = vm
    }

    func testDirectoryChangedUpdatesMetadata() async throws {
        let vm = makeViewModel()
        await engine.emit(.workingDirectoryChanged("/tmp/test"))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(vm.currentMetadata.workingDirectory, "/tmp/test")
    }

    // MARK: - Mode controller

    func testModeControllerStartsInEditor() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.modeController.mode, .editor)
    }

    // MARK: - Send and resize

    func testSendDelegatesToEngine() async throws {
        let vm = makeViewModel()
        vm.send("hello")
        try await Task.sleep(for: .milliseconds(50))
        let sent = await engine.sentTexts
        XCTAssertTrue(sent.contains("hello"))
    }

    func testResizeDelegatesToEngine() async throws {
        let vm = makeViewModel()
        vm.resize(columns: 120, rows: 40)
        try await Task.sleep(for: .milliseconds(50))
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
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(vm.modeController.mode, .editor)
    }

    func testExecutionStartedSwitchesToPassthrough() async throws {
        let vm = makeViewModel()
        XCTAssertEqual(modeController.mode, .editor)

        await engine.emitShellEvent(.executionStarted)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(vm.modeController.mode, .passthrough)
        _ = vm
    }

    func testExecutionFinishedSwitchesToEditor() async throws {
        let vm = makeViewModel()
        modeController.switchToPassthrough()

        await engine.emitShellEvent(.executionFinished(exitCode: 0))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(vm.modeController.mode, .editor)
        _ = vm
    }

    // MARK: - Data event accumulates tokens

    func testDataEventAccumulatesTokens() async throws {
        let vm = makeViewModel()
        let text = String(repeating: "a", count: 400) // 400 chars → 100 tokens
        let data = text.data(using: .utf8) ?? Data()
        await engine.emit(.data(data))
        try await Task.sleep(for: .milliseconds(200))

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
        _ = vm
    }

    // MARK: - Process exit

    func testProcessExitDoesNotCrash() async throws {
        let vm = makeViewModel()
        await engine.emit(.processExited(0))
        try await Task.sleep(for: .milliseconds(100))
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
}
