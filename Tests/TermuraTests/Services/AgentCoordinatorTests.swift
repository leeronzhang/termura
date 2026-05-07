import Foundation
@testable import Termura
import XCTest

/// Tests for AgentCoordinator — agent detection from output,
/// buffer management, state updates, and prefix stripping.
@MainActor
final class AgentCoordinatorTests: XCTestCase {
    private var sessionID = SessionID()
    private var sessionStore = MockSessionStore()
    private var metricsCollector = MockMetricsCollector()
    private var agentStateStore = MockAgentStateStore()

    override func setUp() async throws {
        sessionID = SessionID()
        let record = SessionRecord(id: sessionID, title: "Terminal")
        sessionStore = MockSessionStore(sessions: [record], activeID: sessionID)
        metricsCollector = MockMetricsCollector()
        agentStateStore = MockAgentStateStore()
    }

    private func makeCoordinator() -> AgentCoordinator {
        AgentCoordinator(
            sessionID: sessionID,
            sessionStore: sessionStore,
            agentStateStore: agentStateStore,
            metricsCollector: metricsCollector
        )
    }

    // MARK: - Output detection

    func testDetectsClaudeCodeFromOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput("Welcome to Claude Code v1.0")
        let detected = await coordinator.hasDetectedAgentFromOutput
        XCTAssertTrue(detected)
        let agentType = await coordinator.lastDetectedAgentType
        XCTAssertEqual(agentType, .claudeCode)
    }

    func testDetectsAiderFromOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput("aider v0.50.1")
        let detected = await coordinator.hasDetectedAgentFromOutput
        XCTAssertTrue(detected)
        let agentType = await coordinator.lastDetectedAgentType
        XCTAssertEqual(agentType, .aider)
    }

    func testDetectsGeminiFromOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput("Gemini CLI starting...")
        let detected = await coordinator.hasDetectedAgentFromOutput
        XCTAssertTrue(detected)
        let agentType = await coordinator.lastDetectedAgentType
        XCTAssertEqual(agentType, .gemini)
    }

    func testDetectsCodexFromOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput(">_ OpenAI Codex")
        let detected = await coordinator.hasDetectedAgentFromOutput
        XCTAssertTrue(detected)
        let agentType = await coordinator.lastDetectedAgentType
        XCTAssertEqual(agentType, .codex)
    }

    func testNoDetectionForIrrelevantOutput() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput("ls -la\ntotal 42\ndrwxr-xr-x")
        let notDetected = await coordinator.hasDetectedAgentFromOutput
        XCTAssertFalse(notDetected)
        let agentTypeNil = await coordinator.lastDetectedAgentType
        XCTAssertNil(agentTypeNil)
    }

    // MARK: - Buffer management

    /// Verify the buffer is bounded at 2×maxLen (amortized trim threshold).
    /// The buffer grows to 2×maxLen before being cut back to maxLen, so after a single
    /// large input the count must be at most 2×maxLen.
    func testBufferCapsAtAmortizedLimit() async {
        let coordinator = makeCoordinator()
        let maxLen = AppConfig.Agent.outputAnalysisSuffixLength
        // Input of 3×maxLen guarantees at least one trim cycle fires.
        let longText = String(repeating: "a", count: 3 * maxLen)
        await coordinator.detectAgentFromOutput(longText)
        let bufferCount = await coordinator.agentDetectionBuffer.count
        XCTAssertLessThanOrEqual(bufferCount, maxLen)
    }

    func testBufferAccumulatesAcrossCalls() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput("Welcome to ")
        let notDetected = await coordinator.hasDetectedAgentFromOutput
        XCTAssertFalse(notDetected)

        await coordinator.detectAgentFromOutput("Claude Code!")
        let detected = await coordinator.hasDetectedAgentFromOutput
        XCTAssertTrue(detected)
    }

    // MARK: - Duplicate detection suppression

    func testSameAgentNotDetectedTwice() async throws {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput("claude code")
        let firstDetect = await coordinator.hasDetectedAgentFromOutput

        await coordinator.detectAgentFromOutput("claude code again")

        XCTAssertTrue(firstDetect)
        try await yieldForDuration(seconds: 0.05)
        let count = await metricsCollector.incrementCount(for: .agentDetected)
        XCTAssertEqual(count, 1)
    }

    // MARK: - Session store updates

    func testDetectionUpdatesSessionAgentType() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput("aider v0.50")
        let session = sessionStore.sessions.first { $0.id == sessionID }
        XCTAssertEqual(session?.agentType, .aider)
    }

    func testDetectionRenamesSession() async {
        let coordinator = makeCoordinator()
        await coordinator.detectAgentFromOutput("claude code")
        let session = sessionStore.sessions.first { $0.id == sessionID }
        XCTAssertEqual(session?.title, AgentType.claudeCode.displayName)
    }

    // MARK: - stripAgentPrefixes

    func testStripAgentPrefixesRemovesMultiCharPrefix() {
        let result = TitleSanitizer.stripAgentPrefixes(">_ Claude Code")
        XCTAssertEqual(result, "Claude Code")
    }

    func testStripAgentPrefixesRemovesUnicodeSymbol() {
        let result = TitleSanitizer.stripAgentPrefixes("\u{2733} Claude Code")
        XCTAssertEqual(result, "Claude Code")
    }

    func testStripAgentPrefixesRemovesChainedPrefixes() {
        let result = TitleSanitizer.stripAgentPrefixes(">_ \u{2605} Title")
        XCTAssertEqual(result, "Title")
    }

    func testStripAgentPrefixesPreservesEmptyFallback() {
        let result = TitleSanitizer.stripAgentPrefixes(">_")
        XCTAssertEqual(result, ">_")
    }

    func testStripAgentPrefixesPreservesPlainTitle() {
        let result = TitleSanitizer.stripAgentPrefixes("My Terminal")
        XCTAssertEqual(result, "My Terminal")
    }

    func testStripAgentPrefixesRemovesBulletPrefix() {
        let result = TitleSanitizer.stripAgentPrefixes("\u{2022} Aider")
        XCTAssertEqual(result, "Aider")
    }

    func testStripAgentPrefixesRemovesArrowPrefix() {
        let result = TitleSanitizer.stripAgentPrefixes("\u{203A} Gemini")
        XCTAssertEqual(result, "Gemini")
    }

    // MARK: - Initial state

    func testInitialStateHasNoDetection() async {
        let coordinator = makeCoordinator()
        let notDetected = await coordinator.hasDetectedAgentFromOutput
        XCTAssertFalse(notDetected)
        let agentTypeNil = await coordinator.lastDetectedAgentType
        XCTAssertNil(agentTypeNil)
        let bufferEmpty = await coordinator.agentDetectionBuffer.isEmpty
        XCTAssertTrue(bufferEmpty)
        // Alert state propagates via riskAlerts / contextWindowAlerts AsyncStreams —
        // AgentCoordinator does not own alert properties directly.
    }
}
