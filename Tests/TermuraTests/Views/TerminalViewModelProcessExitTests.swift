import Foundation
@testable import Termura
import XCTest

// Sendable safety: synchronization is fully guarded by `NSCondition`; shared state
// (`isBlocked`) is only read or written while the condition lock is held.
private final class OutputGate: @unchecked Sendable { // swiftlint:disable:this unchecked_sendable_documentation
    private let condition = NSCondition()
    private var isBlocked = true

    func waitIfBlocked() {
        condition.lock()
        defer { condition.unlock() }
        while isBlocked {
            condition.wait()
        }
    }

    func release() {
        condition.lock()
        isBlocked = false
        condition.broadcast()
        condition.unlock()
    }
}

private actor BlockingTokenCountingService: TokenCountingServiceProtocol {
    nonisolated let outputGate = OutputGate()
    private var breakdowns: [SessionID: TokenEstimateBreakdown] = [:]

    private func update(
        sessionID: SessionID,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedTokens: Int? = nil
    ) {
        let current = breakdowns[sessionID] ?? .zero
        breakdowns[sessionID] = TokenEstimateBreakdown(
            inputTokens: inputTokens ?? current.inputTokens,
            outputTokens: outputTokens ?? current.outputTokens,
            cachedTokens: cachedTokens ?? current.cachedTokens
        )
    }

    func accumulateInput(for sessionID: SessionID, text: String) {
        let current = breakdowns[sessionID] ?? .zero
        update(sessionID: sessionID, inputTokens: current.inputTokens + max(1, text.count / 4))
    }

    func accumulateOutput(for sessionID: SessionID, text: String) {
        outputGate.waitIfBlocked()
        let current = breakdowns[sessionID] ?? .zero
        update(sessionID: sessionID, outputTokens: current.outputTokens + max(1, text.count / 4))
    }

    func accumulateCached(for sessionID: SessionID, count: Int) {
        let current = breakdowns[sessionID] ?? .zero
        update(sessionID: sessionID, cachedTokens: current.cachedTokens + count)
    }

    func estimatedTokens(for sessionID: SessionID) -> Int {
        let breakdown = breakdowns[sessionID] ?? .zero
        return breakdown.inputTokens + breakdown.outputTokens + breakdown.cachedTokens
    }

    func tokenBreakdown(for sessionID: SessionID) -> TokenEstimateBreakdown {
        breakdowns[sessionID] ?? .zero
    }

    func applyParsedStats(for sessionID: SessionID, inputTokens: Int, outputTokens: Int, cachedTokens: Int) {
        breakdowns[sessionID] = TokenEstimateBreakdown(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens
        )
    }

    func reset(for sessionID: SessionID) {
        breakdowns.removeValue(forKey: sessionID)
    }

    nonisolated func releaseOutput() {
        outputGate.release()
    }
}

@MainActor
final class TerminalViewModelProcessExitTests: XCTestCase {
    private var engine = MockTerminalEngine()
    private var sessionStore = MockSessionStore()
    private var outputStore = OutputStore(sessionID: SessionID())
    private var modeController = InputModeController()
    private var sessionID = SessionID()
    private var testClock = TestClock()

    override func setUp() async throws {
        sessionID = SessionID()
        engine = MockTerminalEngine()
        sessionStore = MockSessionStore()
        outputStore = OutputStore(sessionID: sessionID)
        modeController = InputModeController()
        testClock = TestClock()
    }

    func testProcessExitWaitsForQueuedOutputBeforeGeneratingHandoff() async throws {
        let blockingTokens = BlockingTokenCountingService()
        let handoffService = MockSessionHandoffService()
        let record = SessionRecord(title: "Queued Output", workingDirectory: "/tmp/project")
        sessionID = record.id
        sessionStore = MockSessionStore(sessions: [record], activeID: record.id)
        sessionStore.projectRoot = "/tmp/project"
        outputStore = OutputStore(sessionID: sessionID)

        let coordinator = AgentCoordinator(
            sessionID: sessionID,
            sessionStore: sessionStore,
            agentStateStore: MockAgentStateStore()
        )
        let processor = OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: blockingTokens
        )
        let services = SessionServices(sessionHandoffService: handoffService)
        let viewModel = TerminalViewModel(TerminalViewModel.Components(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: modeController,
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: services,
            clock: testClock
        ))
        _ = await viewModel.agentCoordinator.agentDetector.detectFromCommand("claude")

        engine.emit(.data(Data("final output before exit\n".utf8)))
        engine.emit(.processExited(0))
        try await yieldForDuration(seconds: 0.05)

        let generateCallCountBeforeRelease = await handoffService.generateCallCount
        XCTAssertEqual(generateCallCountBeforeRelease, 0)

        blockingTokens.releaseOutput()
        await viewModel.waitForIdle()

        let generateCallCountAfterRelease = await handoffService.generateCallCount
        XCTAssertEqual(generateCallCountAfterRelease, 1)
    }
}
