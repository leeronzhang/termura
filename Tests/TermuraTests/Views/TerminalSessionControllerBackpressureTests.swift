import Foundation
@testable import Termura
import XCTest

@MainActor
final class SessionBackpressureTests: XCTestCase {
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

    private func makeViewModel() -> TerminalViewModel {
        let coordinator = AgentCoordinator(
            sessionID: sessionID,
            sessionStore: sessionStore,
            agentStateStore: MockAgentStateStore()
        )
        let processor = OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: tokenService
        )
        let services = SessionServices()
        return TerminalViewModel(TerminalViewModel.Components(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: modeController,
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: services
        ))
    }

    func testOutputAtCapacityIsCoalescedAndEventuallyProcessed() async throws {
        let vm = makeViewModel()
        let gate = BlockingGate()
        let executor = vm.controller.taskExecutor
        let trackedLimit = AppConfig.Runtime.maxConcurrentSessionTasks * AppConfig.Runtime.taskQueueDepthMultiplier

        for _ in 0 ..< trackedLimit {
            executor.spawnDetached {
                await gate.wait()
            }
        }
        try await waitUntil { executor.isAtCapacity }

        let payload = String(repeating: "coalesced output ", count: 200)
        engine.emit(.data(Data(payload.utf8)))

        try await waitUntil {
            vm.controller.pendingOutputBuffer?.text.contains("coalesced output") == true
        }

        await gate.open()

        try await waitUntil { [self] in
            await tokenService.estimatedTokens(for: sessionID) > 0
        }
        try await waitUntil {
            await vm.waitForIdle()
            return vm.controller.pendingOutputBuffer == nil
        }

        let estimatedTokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(estimatedTokens, 0)
        XCTAssertNil(vm.controller.pendingOutputBuffer)
    }
}

private actor BlockingGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        for continuation in pending {
            continuation.resume()
        }
    }
}
