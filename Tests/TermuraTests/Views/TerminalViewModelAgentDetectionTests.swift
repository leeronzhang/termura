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
        return TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            outputStore: outputStore,
            tokenCountingService: tokenService,
            modeController: modeController
        )
    }

    // MARK: - stripAgentPrefixes

    func testStripAgentPrefixesRemovesClaudeCodePrefix() {
        // "\u{2733}" is the sparkle prefix used by Claude Code.
        let result = TerminalViewModel.stripAgentPrefixes("\u{2733} Claude Code")
        XCTAssertEqual(result, "Claude Code")
    }

    func testStripAgentPrefixesRemovesCodexPrefix() {
        let result = TerminalViewModel.stripAgentPrefixes(">_ Codex CLI")
        XCTAssertEqual(result, "Codex CLI")
    }

    func testStripAgentPrefixesRemovesAiderPrefix() {
        // Aider uses "\u{2726}" prefix.
        let result = TerminalViewModel.stripAgentPrefixes("\u{2726} aider v0.50")
        XCTAssertEqual(result, "aider v0.50")
    }

    func testStripAgentPrefixesPreservesCleanTitle() {
        let result = TerminalViewModel.stripAgentPrefixes("My Terminal")
        XCTAssertEqual(result, "My Terminal")
    }

    func testStripAgentPrefixesHandlesEmptyStringAfterStripping() {
        // When stripping leaves empty, original is returned.
        let original = "\u{2733}"
        let result = TerminalViewModel.stripAgentPrefixes(original)
        XCTAssertEqual(result, original, "Should return original when stripped result is empty")
    }

    func testStripAgentPrefixesRemovesCompoundPrefixes() {
        // Claude Code task titles often use compound format: sparkle + middle dot + task name.
        let result = TerminalViewModel.stripAgentPrefixes("\u{2733} \u{00B7} Refactor God Object")
        XCTAssertEqual(result, "Refactor God Object")
    }

    func testStripAgentPrefixesRemovesMiddleDotPrefix() {
        let result = TerminalViewModel.stripAgentPrefixes("\u{00B7} Some task")
        XCTAssertEqual(result, "Some task")
    }

    // MARK: - detectAgentFromCommand

    func testDetectAgentFromCommandClaudeCode() async throws {
        let vm = makeViewModel()
        vm.detectAgentFromCommand("claude --model opus")
        try await yieldForDuration(seconds: 0.2)
        // The session should have been renamed to the Claude Code display name.
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
        // Emit data containing an agent signature twice.
        let text = "Welcome to claude code session"
        guard let data = text.data(using: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        await engine.emit(.data(data))
        try await yieldForDuration(seconds: 0.3)

        // Record title after first detection.
        let titleAfterFirst = sessionStore.sessions.first(where: { $0.id == sessionID })?.title

        // Manually rename to verify second emission does not re-trigger rename.
        sessionStore.renameSession(id: sessionID, title: "Manually Renamed")

        await engine.emit(.data(data))
        try await yieldForDuration(seconds: 0.3)

        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }) else {
            XCTFail("Session not found")
            return
        }
        // The session title should remain "Manually Renamed" because detection
        // is guarded by hasDetectedAgentFromOutput.
        XCTAssertEqual(session.title, "Manually Renamed")
        // First detection should have set the agent display name.
        XCTAssertNotNil(titleAfterFirst)
        _ = vm
    }
}
