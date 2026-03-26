import Foundation
import XCTest
@testable import Termura

// MARK: - Mock context injection service

private actor MockContextInjectionService: ContextInjectionServiceProtocol {
    private(set) var buildCallCount = 0
    var stubbedText: String? = "injected context"

    func buildInjectionText(projectRoot: String) async -> String? {
        buildCallCount += 1
        return stubbedText
    }
}

// MARK: - Mock session handoff service

private actor MockSessionHandoffService: SessionHandoffServiceProtocol {
    private(set) var generateCallCount = 0

    func generateHandoff(
        session: SessionRecord,
        chunks: [OutputChunk],
        agentState: AgentState
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
    private var engine: MockTerminalEngine!
    private var sessionStore: MockSessionStore!
    private var outputStore: OutputStore!
    private var tokenService: TokenCountingService!
    private var modeController: InputModeController!
    private var sessionID: SessionID!
    private var testClock: TestClock!

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
        TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            outputStore: outputStore,
            tokenCountingService: tokenService,
            modeController: modeController,
            isRestoredSession: isRestoredSession,
            contextInjectionService: contextInjectionService,
            sessionHandoffService: sessionHandoffService,
            clock: testClock
        )
    }

    // MARK: - Context injection

    func testRestoredSessionTriggersContextInjection() async throws {
        let mockInjection = MockContextInjectionService()
        let vm = makeViewModel(
            isRestoredSession: true,
            contextInjectionService: mockInjection
        )
        // Set a non-empty working directory so the guard passes.
        vm.currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: "/tmp/project"
        )
        vm.injectContextIfNeeded()
        try await yieldForDuration(seconds: 0.2)
        let count = await mockInjection.buildCallCount
        XCTAssertEqual(count, 1)
    }

    func testInjectionHappensOnlyOnce() async throws {
        let mockInjection = MockContextInjectionService()
        let vm = makeViewModel(
            isRestoredSession: true,
            contextInjectionService: mockInjection
        )
        vm.currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: "/tmp/project"
        )
        vm.injectContextIfNeeded()
        vm.injectContextIfNeeded()
        try await yieldForDuration(seconds: 0.2)
        let count = await mockInjection.buildCallCount
        XCTAssertEqual(count, 1, "Injection should fire exactly once regardless of repeated calls")
    }

    func testInjectionSkippedWhenServiceReturnsNil() async throws {
        let mockInjection = MockContextInjectionService()
        await mockInjection.setStubbedText(nil)
        let vm = makeViewModel(
            isRestoredSession: true,
            contextInjectionService: mockInjection
        )
        vm.currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: "/tmp/project"
        )
        vm.injectContextIfNeeded()
        try await yieldForDuration(seconds: 0.2)
        // Service was called, but engine should NOT have received text.
        let sent = await engine.sentTexts
        XCTAssertFalse(sent.contains(where: { $0.contains("injected") }))
    }

    func testInjectionSkippedWhenWorkingDirectoryEmpty() async throws {
        let mockInjection = MockContextInjectionService()
        let vm = makeViewModel(
            isRestoredSession: true,
            contextInjectionService: mockInjection
        )
        // Default metadata has homeDirectory which is non-empty,
        // so explicitly set empty working directory.
        vm.currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: ""
        )
        vm.injectContextIfNeeded()
        try await yieldForDuration(seconds: 0.2)
        let count = await mockInjection.buildCallCount
        XCTAssertEqual(count, 0, "Should skip injection when working directory is empty")
    }

    // MARK: - Handoff on process exit

    func testHandoffGeneratedOnProcessExit() async throws {
        let mockHandoff = MockSessionHandoffService()
        let record = sessionStore.createSession(title: "Test")
        sessionID = record.id
        // Rebuild stores with matching session ID.
        outputStore = OutputStore(sessionID: sessionID)
        sessionStore.updateWorkingDirectory(id: sessionID, path: "/tmp/project")

        let vm = TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            outputStore: outputStore,
            tokenCountingService: tokenService,
            modeController: modeController,
            sessionHandoffService: mockHandoff,
            clock: testClock
        )
        // Pre-detect an agent so handoff guard passes.
        let agentDet = vm.agentDetector
        _ = await agentDet.detectFromCommand("claude")

        await vm.generateHandoffIfNeeded(exitCode: 0)
        try await yieldForDuration(seconds: 0.2)
        let count = await mockHandoff.generateCallCount
        XCTAssertEqual(count, 1)
    }

    func testNoHandoffWhenSessionHandoffServiceNil() async throws {
        let vm = makeViewModel(sessionHandoffService: nil)
        // Should complete without crash even with no handoff service.
        await vm.generateHandoffIfNeeded(exitCode: 0)
        XCTAssertNotNil(vm)
    }
}

// MARK: - Helper to set stubbed value on actor

private extension MockContextInjectionService {
    func setStubbedText(_ text: String?) {
        stubbedText = text
    }
}
