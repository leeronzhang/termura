import Foundation
import XCTest
@testable import Termura

/// Tests for AgentCoordinator — agent detection from output,
/// buffer management, state updates, and prefix stripping.
@MainActor
final class AgentCoordinatorTests: XCTestCase {
    private var sessionID = SessionID()
    private var sessionStore = MockSessionStore()
    private var metricsCollector = MockMetricsCollector()

    override func setUp() async throws {
        sessionID = SessionID()
        let record = SessionRecord(id: sessionID, title: "Terminal")
        sessionStore = MockSessionStore(sessions: [record], activeID: sessionID)
        metricsCollector = MockMetricsCollector()
    }

    private func makeCoordinator() -> AgentCoordinator {
        AgentCoordinator(
            sessionID: sessionID,
            metricsCollector: metricsCollector
        )
    }

    // MARK: - Output detection

    func testDetectsClaudeCodeFromOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(
            "Welcome to Claude Code v1.0",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        XCTAssertTrue(coordinator.hasDetectedAgentFromOutput)
        XCTAssertEqual(coordinator.lastDetectedAgentType, .claudeCode)
    }

    func testDetectsAiderFromOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(
            "aider v0.50.1",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        XCTAssertTrue(coordinator.hasDetectedAgentFromOutput)
        XCTAssertEqual(coordinator.lastDetectedAgentType, .aider)
    }

    func testDetectsGeminiFromOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(
            "Gemini CLI starting...",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        XCTAssertTrue(coordinator.hasDetectedAgentFromOutput)
        XCTAssertEqual(coordinator.lastDetectedAgentType, .gemini)
    }

    func testDetectsCodexFromOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(
            ">_ OpenAI Codex",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        XCTAssertTrue(coordinator.hasDetectedAgentFromOutput)
        XCTAssertEqual(coordinator.lastDetectedAgentType, .codex)
    }

    func testNoDetectionForIrrelevantOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(
            "ls -la\ntotal 42\ndrwxr-xr-x",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        XCTAssertFalse(coordinator.hasDetectedAgentFromOutput)
        XCTAssertNil(coordinator.lastDetectedAgentType)
    }

    // MARK: - Buffer management

    func testBufferCapsAtMaxLength() async {
        let coordinator = makeCoordinator()
        let longText = String(repeating: "a", count: AppConfig.Agent.outputAnalysisSuffixLength + 500)
        await coordinator.detectAgentFromOutput(
            longText,
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        XCTAssertLessThanOrEqual(
            coordinator.agentDetectionBuffer.count,
            AppConfig.Agent.outputAnalysisSuffixLength
        )
    }

    func testBufferAccumulatesAcrossCalls() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(
            "Welcome to ",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        XCTAssertFalse(coordinator.hasDetectedAgentFromOutput)

        await coordinator.detectAgentFromOutput(
            "Claude Code!",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        XCTAssertTrue(coordinator.hasDetectedAgentFromOutput)
    }

    // MARK: - Duplicate detection suppression

    func testSameAgentNotDetectedTwice() async throws {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(
            "claude code",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        let firstDetect = coordinator.hasDetectedAgentFromOutput

        await coordinator.detectAgentFromOutput(
            "claude code again",
            sessionStore: sessionStore,
            sessionID: sessionID
        )

        XCTAssertTrue(firstDetect)
        try await yieldForDuration(seconds: 0.05)
        let count = await metricsCollector.incrementCount(for: .agentDetected)
        XCTAssertEqual(count, 1)
    }

    // MARK: - Session store updates

    func testDetectionUpdatesSessionAgentType() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(
            "aider v0.50",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        let session = sessionStore.sessions.first { $0.id == sessionID }
        XCTAssertEqual(session?.agentType, .aider)
    }

    func testDetectionRenamesSession() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(
            "claude code",
            sessionStore: sessionStore,
            sessionID: sessionID
        )
        let session = sessionStore.sessions.first { $0.id == sessionID }
        XCTAssertEqual(session?.title, AgentType.claudeCode.displayName)
    }

    // MARK: - stripAgentPrefixes

    func testStripAgentPrefixesRemovesMultiCharPrefix() {
        let result = AgentCoordinator.stripAgentPrefixes(">_ Claude Code")
        XCTAssertEqual(result, "Claude Code")
    }

    func testStripAgentPrefixesRemovesUnicodeSymbol() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{2733} Claude Code")
        XCTAssertEqual(result, "Claude Code")
    }

    func testStripAgentPrefixesRemovesChainedPrefixes() {
        let result = AgentCoordinator.stripAgentPrefixes(">_ \u{2605} Title")
        XCTAssertEqual(result, "Title")
    }

    func testStripAgentPrefixesPreservesEmptyFallback() {
        let result = AgentCoordinator.stripAgentPrefixes(">_")
        XCTAssertEqual(result, ">_")
    }

    func testStripAgentPrefixesPreservesPlainTitle() {
        let result = AgentCoordinator.stripAgentPrefixes("My Terminal")
        XCTAssertEqual(result, "My Terminal")
    }

    func testStripAgentPrefixesRemovesBulletPrefix() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{2022} Aider")
        XCTAssertEqual(result, "Aider")
    }

    func testStripAgentPrefixesRemovesArrowPrefix() {
        let result = AgentCoordinator.stripAgentPrefixes("\u{203A} Gemini")
        XCTAssertEqual(result, "Gemini")
    }

    // MARK: - Initial state

    func testInitialStateHasNoDetection() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.hasDetectedAgentFromOutput)
        XCTAssertNil(coordinator.lastDetectedAgentType)
        XCTAssertTrue(coordinator.agentDetectionBuffer.isEmpty)
        XCTAssertNil(coordinator.pendingRiskAlert)
        XCTAssertNil(coordinator.contextWindowAlert)
    }
}
