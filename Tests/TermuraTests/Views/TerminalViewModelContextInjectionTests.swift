import Foundation
@testable import Termura
import XCTest

// MARK: - Mock context injection service

private actor LocalMockContextInjectionService: ContextInjectionServiceProtocol {
    private(set) var buildCallCount = 0
    var stubbedText: String? = "injected context"

    func buildInjectionText(projectRoot: String) async -> String? {
        buildCallCount += 1
        return stubbedText
    }
}

// MARK: - Mock session handoff service

private actor LocalMockSessionHandoffService: SessionHandoffServiceProtocol {
    private(set) var generateCallCount = 0

    func generateHandoff(
        session: SessionRecord,
        chunks: [OutputChunk],
        agentState: AgentState,
        projectRoot: String
    ) async throws {
        generateCallCount += 1
    }

    func readExistingContext(projectRoot: String) async -> HandoffContext? {
        nil
    }
}

// MARK: - Tests

@MainActor
final class TerminalViewModelContextInjectionTests: XCTestCase {
    private var engine = MockTerminalEngine()
    private var sessionStore = MockSessionStore()
    private var outputStore = OutputStore(sessionID: SessionID())
    private var tokenService = TokenCountingService()
    private var modeController = InputModeController()
    private var sessionID = SessionID()
    private var testClock = TestClock()

    override func setUp() async throws {
        sessionID = SessionID()
        engine = MockTerminalEngine()
        sessionStore = MockSessionStore()
        outputStore = OutputStore(sessionID: sessionID)
        tokenService = TokenCountingService()
        modeController = InputModeController()
        testClock = TestClock()
    }

    private func makeViewModel(
        isRestoredSession: Bool = false,
        contextInjectionService: (any ContextInjectionServiceProtocol)? = nil,
        sessionHandoffService: (any SessionHandoffServiceProtocol)? = nil
    ) -> TerminalViewModel {
        let coordinator = AgentCoordinator(sessionID: sessionID, sessionStore: sessionStore, agentStateStore: MockAgentStateStore())
        let processor = OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: tokenService
        )
        let services = SessionServices(
            contextInjectionService: contextInjectionService,
            sessionHandoffService: sessionHandoffService,
            isRestoredSession: isRestoredSession
        )
        return TerminalViewModel(TerminalViewModel.Components(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: modeController,
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: services,
            clock: testClock
        ))
    }

    // MARK: - Context injection

    func testRestoredSessionTriggersContextInjection() async throws {
        let mockInjection = LocalMockContextInjectionService()
        let vm = makeViewModel(
            isRestoredSession: true,
            contextInjectionService: mockInjection
        )
        // Set a non-empty working directory so the guard passes.
        vm.currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: "/tmp/project"
        )
        await vm.sessionServices.injectContextIfNeeded(
            workingDirectory: vm.currentMetadata.workingDirectory,
            engine: engine,
            clock: testClock
        )
        await vm.sessionServices.flushPendingInjection()
        let count = await mockInjection.buildCallCount
        XCTAssertEqual(count, 1)
    }

    func testInjectionHappensOnlyOnce() async throws {
        let mockInjection = LocalMockContextInjectionService()
        let vm = makeViewModel(
            isRestoredSession: true,
            contextInjectionService: mockInjection
        )
        vm.currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: "/tmp/project"
        )
        await vm.sessionServices.injectContextIfNeeded(
            workingDirectory: vm.currentMetadata.workingDirectory,
            engine: engine,
            clock: testClock
        )
        await vm.sessionServices.injectContextIfNeeded(
            workingDirectory: vm.currentMetadata.workingDirectory,
            engine: engine,
            clock: testClock
        )
        await vm.sessionServices.flushPendingInjection()
        let count = await mockInjection.buildCallCount
        XCTAssertEqual(count, 1, "Injection should fire exactly once regardless of repeated calls")
    }

    func testInjectionSkippedWhenServiceReturnsNil() async throws {
        let mockInjection = LocalMockContextInjectionService()
        await mockInjection.setStubbedText(nil)
        let vm = makeViewModel(
            isRestoredSession: true,
            contextInjectionService: mockInjection
        )
        vm.currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: "/tmp/project"
        )
        await vm.sessionServices.injectContextIfNeeded(
            workingDirectory: vm.currentMetadata.workingDirectory,
            engine: engine,
            clock: testClock
        )
        await vm.sessionServices.flushPendingInjection()
        // Service was called, but engine should NOT have received text.
        let sent = engine.sentTexts
        XCTAssertFalse(sent.contains(where: { $0.contains("injected") }))
    }

    func testInjectionSkippedWhenWorkingDirectoryEmpty() async throws {
        let mockInjection = LocalMockContextInjectionService()
        let vm = makeViewModel(
            isRestoredSession: true,
            contextInjectionService: mockInjection
        )
        vm.currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: ""
        )
        await vm.sessionServices.injectContextIfNeeded(
            workingDirectory: vm.currentMetadata.workingDirectory,
            engine: engine,
            clock: testClock
        )
        let count = await mockInjection.buildCallCount
        XCTAssertEqual(count, 0, "Should skip injection when working directory is empty")
    }

    // MARK: - Handoff on process exit

    func testHandoffGeneratedOnProcessExit() async throws {
        let mockHandoff = LocalMockSessionHandoffService()
        let record = sessionStore.createSession(title: "Test")
        sessionID = record.id
        outputStore = OutputStore(sessionID: sessionID)
        sessionStore.updateWorkingDirectory(id: sessionID, path: "/tmp/project")

        let coordinator = AgentCoordinator(sessionID: sessionID, sessionStore: sessionStore, agentStateStore: MockAgentStateStore())
        let processor = OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: tokenService
        )
        let services = SessionServices(
            sessionHandoffService: mockHandoff
        )
        let vm = TerminalViewModel(TerminalViewModel.Components(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: modeController,
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: services,
            clock: testClock
        ))
        // Pre-detect an agent so handoff guard passes.
        let agentDet = vm.agentCoordinator.agentDetector
        _ = await agentDet.detectFromCommand("claude")

        let agentState = await agentDet.buildState()
        let session = sessionStore.sessions.first { $0.id == sessionID }
        let chunks = Array(outputStore.chunks)
        await services.generateHandoffIfNeeded(
            session: session,
            chunks: chunks,
            agentState: agentState,
            projectRoot: "/tmp/test-project"
        )
        await services.flushPendingHandoff()
        let count = await mockHandoff.generateCallCount
        XCTAssertEqual(count, 1)
    }

    func testNoHandoffWhenSessionHandoffServiceNil() async throws {
        let vm = makeViewModel(sessionHandoffService: nil)
        let agentState = await vm.agentCoordinator.agentDetector.buildState()
        await vm.sessionServices.generateHandoffIfNeeded(
            session: nil,
            chunks: [],
            agentState: agentState,
            projectRoot: "/tmp/test-project"
        )
        XCTAssertNotNil(vm)
    }
}

// MARK: - Helper to set stubbed value on actor

private extension LocalMockContextInjectionService {
    func setStubbedText(_ text: String?) {
        stubbedText = text
    }
}
