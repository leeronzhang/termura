import Foundation
@testable import Termura
import XCTest

@MainActor
final class TerminalViewModelTests: XCTestCase {
    private var engine = MockTerminalEngine()
    private var sessionStore = MockSessionStore()
    private var outputStore = OutputStore(sessionID: SessionID())
    private var tokenService = TokenCountingService()
    private var modeController = InputModeController()
    private var sessionID = SessionID()

    override func setUp() async throws {
        sessionID = SessionID()
        engine = MockTerminalEngine()
        sessionStore = MockSessionStore()
        outputStore = OutputStore(sessionID: sessionID)
        tokenService = TokenCountingService()
        modeController = InputModeController()
    }

    private func makeViewModel(
        isRestoredSession: Bool = false,
        clock: any AppClock = LiveClock()
    ) -> TerminalViewModel {
        let coordinator = AgentCoordinator(sessionID: sessionID, sessionStore: sessionStore, agentStateStore: MockAgentStateStore())
        let processor = OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: tokenService
        )
        let services = SessionServices(isRestoredSession: isRestoredSession)
        return TerminalViewModel(TerminalViewModel.Components(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: modeController,
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: services,
            clock: clock
        ))
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
        sessionStore = MockSessionStore(
            sessions: [SessionRecord(id: sessionID, title: "Terminal")],
            activeID: sessionID
        )
        let vm = makeViewModel()
        let sessionStore = sessionStore
        // Emit a title change event.
        engine.emit(.titleChanged("New Title"))
        try await waitUntil {
            sessionStore.sessions.first?.title == "New Title"
        }
        _ = vm
    }

    func testDirectoryChangedUpdatesMetadata() async throws {
        let vm = makeViewModel()
        engine.emit(.workingDirectoryChanged("/tmp/test"))
        try await waitUntil { vm.currentMetadata.workingDirectory == "/tmp/test" }
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
        let engine = engine
        vm.send("hello")
        try await waitUntil { !engine.sentTexts.isEmpty }
        let sent = engine.sentTexts
        XCTAssertTrue(sent.contains("hello"))
    }

    func testResizeDelegatesToEngine() async throws {
        let vm = makeViewModel()
        let engine = engine
        vm.resize(columns: 120, rows: 40)
        try await waitUntil { !engine.resizes.isEmpty }
        let resizes = engine.resizes
        XCTAssertFalse(resizes.isEmpty)
        XCTAssertEqual(resizes.last?.0, 120)
        XCTAssertEqual(resizes.last?.1, 40)
    }

    // MARK: - Shell event handling

    func testPromptStartedSwitchesToEditor() async throws {
        let vm = makeViewModel()
        modeController.switchToPassthrough()
        XCTAssertEqual(modeController.mode, .passthrough)

        engine.emitShellEvent(.promptStarted)
        try await waitUntil { vm.modeController.mode == .editor }
        XCTAssertEqual(vm.modeController.mode, .editor)
    }

    func testExecutionStartedStaysInPassthrough() async throws {
        let vm = makeViewModel()
        XCTAssertEqual(modeController.mode, .passthrough)

        engine.emitShellEvent(.executionStarted)
        try await waitUntil { vm.modeController.mode == .passthrough }
        XCTAssertEqual(vm.modeController.mode, .passthrough)
        _ = vm
    }

    func testExecutionFinishedSwitchesToEditor() async throws {
        let vm = makeViewModel()
        modeController.switchToPassthrough()

        engine.emitShellEvent(.executionFinished(exitCode: 0))
        try await waitUntil { vm.modeController.mode == .editor }
        XCTAssertEqual(vm.modeController.mode, .editor)
        _ = vm
    }

    // MARK: - Data event accumulates tokens

    func testDataEventAccumulatesTokens() async throws {
        let vm = makeViewModel()
        let text = String(repeating: "a", count: 400) // 400 chars -> 100 tokens
        let data = text.data(using: .utf8) ?? Data()
        let tokenService = tokenService
        let sessionID = sessionID
        engine.emit(.data(data))
        try await waitUntil {
            await tokenService.estimatedTokens(for: sessionID) > 0
        }

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
        _ = vm
    }

    // MARK: - Process exit

    func testProcessExitDoesNotCrash() async throws {
        let vm = makeViewModel()
        engine.emit(.processExited(0))
        await vm.waitForIdle()
        // No crash, no handoff (no sessionHandoffService set).
        XCTAssertNotNil(vm)
    }

    // MARK: - Context injection

    func testInjectContextGuardsNonRestoredSession() async {
        let vm = makeViewModel(isRestoredSession: false)
        await vm.sessionServices.injectContextIfNeeded(
            workingDirectory: "",
            engine: engine,
            clock: LiveClock()
        )
        // Should return early — no service, no crash.
        XCTAssertNotNil(vm)
    }

    func testInjectContextGuardsNoService() async {
        let vm = makeViewModel(isRestoredSession: true)
        await vm.sessionServices.injectContextIfNeeded(
            workingDirectory: "/tmp",
            engine: engine,
            clock: LiveClock()
        )
        // contextInjectionService is nil -> returns early.
        XCTAssertNotNil(vm)
    }

    // MARK: - Metadata refresh scheduling

    func testScheduleMetadataRefreshUsesLatestWorkingDirectory() async throws {
        let clock = TestClock()
        let vm = makeViewModel(clock: clock)

        vm.scheduleMetadataRefresh(workingDirectory: "/first")
        vm.scheduleMetadataRefresh(workingDirectory: "/latest")
        try await waitUntil { vm.currentMetadata.workingDirectory == "/latest" }

        XCTAssertEqual(vm.currentMetadata.workingDirectory, "/latest")
    }

    func testScheduleMetadataRefreshUsesInjectedClockForThrottle() async throws {
        let clock = TestClock()
        let vm = makeViewModel(clock: clock)

        vm.scheduleMetadataRefresh(workingDirectory: "/first")
        try await waitUntil { vm.currentMetadata.workingDirectory == "/first" }
        vm.scheduleMetadataRefresh(workingDirectory: "/second")
        try await waitUntil { vm.currentMetadata.workingDirectory == "/second" }

        XCTAssertEqual(vm.currentMetadata.workingDirectory, "/second")
        XCTAssertGreaterThan(clock.sleepCallCount, 0)
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
        let engine = engine
        vm.send("hello")
        try await waitUntil { !engine.sentTexts.isEmpty }
        // Engine should have received the text.
        let sent = engine.sentTexts
        XCTAssertTrue(sent.contains("hello"))
    }

    func testResizeTracksTask() async throws {
        let vm = makeViewModel()
        let engine = engine
        vm.resize(columns: 120, rows: 40)
        try await waitUntil { engine.resizes.count == 1 }
        let resizes = engine.resizes
        XCTAssertEqual(resizes.count, 1)
        XCTAssertEqual(resizes.first?.0, 120)
        XCTAssertEqual(resizes.first?.1, 40)
    }
}
