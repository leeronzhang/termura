import Foundation
import XCTest
@testable import Termura

@MainActor
final class TerminalViewModelAgentDetectionTests: XCTestCase {
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

    private func makeViewModel() -> TerminalViewModel {
        let record = sessionStore.createSession(title: "Terminal")
        sessionID = record.id
        outputStore = OutputStore(sessionID: sessionID)
        let coordinator = AgentCoordinator(sessionID: sessionID)
        let processor = OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: tokenService
        )
        let services = SessionServices()
        return TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: modeController,
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: services
        )
    }

    // MARK: - stripAgentPrefixes

    func testStripAgentPrefixesRemovesClaudeCodePrefix() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{2733} Claude Code")
        XCTAssertEqual(result, "Claude Code")
    }

    func testStripAgentPrefixesRemovesCodexPrefix() {
        let result = AgentCoordinator.stripAgentPrefixes(">_ Codex CLI")
        XCTAssertEqual(result, "Codex CLI")
    }

    func testStripAgentPrefixesRemovesAiderPrefix() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{2726} aider v0.50")
        XCTAssertEqual(result, "aider v0.50")
    }

    func testStripAgentPrefixesPreservesCleanTitle() {
        let result = AgentCoordinator.stripAgentPrefixes("My Terminal")
        XCTAssertEqual(result, "My Terminal")
    }

    func testStripAgentPrefixesHandlesEmptyStringAfterStripping() {
        let original = "\u{2733}"
        let result = AgentCoordinator.stripAgentPrefixes(original)
        XCTAssertEqual(result, original, "Should return original when stripped result is empty")
    }

    func testStripAgentPrefixesRemovesCompoundPrefixes() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{2733} \u{00B7} Refactor God Object")
        XCTAssertEqual(result, "Refactor God Object")
    }

    func testStripAgentPrefixesRemovesMiddleDotPrefix() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{00B7} Some task")
        XCTAssertEqual(result, "Some task")
    }

    func testStripAgentPrefixesRemovesBlackCircle() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{25CF} Running task")
        XCTAssertEqual(result, "Running task")
    }

    func testStripAgentPrefixesRemovesBulletOperator() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{2219} Fix optional string abuse")
        XCTAssertEqual(result, "Fix optional string abuse")
    }

    func testStripAgentPrefixesRemovesHeavyAngleQuotation() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{276F} prompt text")
        XCTAssertEqual(result, "prompt text")
    }

    func testStripAgentPrefixesRemovesCheckMark() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{2714} Done task")
        XCTAssertEqual(result, "Done task")
    }

    // MARK: - detectAgentFromCommand

    func testDetectAgentFromCommandClaudeCode() async throws {
        let vm = makeViewModel()
        vm.detectAgentFromCommand("claude --model opus")
        try await yieldForDuration(seconds: 0.2)
        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }) else {
            XCTFail("Session not found")
            return
        }
        XCTAssertEqual(session.title, AgentType.claudeCode.displayName)
    }

    func testDetectAgentFromCommandCodex() async throws {
        let vm = makeViewModel()
        vm.detectAgentFromCommand("codex run tests")
        try await yieldForDuration(seconds: 0.2)
        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }) else {
            XCTFail("Session not found")
            return
        }
        XCTAssertEqual(session.title, AgentType.codex.displayName)
    }

    // MARK: - detectAgentFromOutput (via output stream)

    func testDetectAgentFromOutputTriggersOnlyOnce() async throws {
        let vm = makeViewModel()
        let text = "Welcome to claude code session"
        guard let data = text.data(using: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        await engine.emit(.data(data))
        try await yieldForDuration(seconds: 0.3)

        let titleAfterFirst = sessionStore.sessions.first(where: { $0.id == sessionID })?.title

        sessionStore.renameSession(id: sessionID, title: "Manually Renamed")

        await engine.emit(.data(data))
        try await yieldForDuration(seconds: 0.3)

        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }) else {
            XCTFail("Session not found")
            return
        }
        XCTAssertEqual(session.title, "Manually Renamed")
        XCTAssertNotNil(titleAfterFirst)
        _ = vm
    }
}
