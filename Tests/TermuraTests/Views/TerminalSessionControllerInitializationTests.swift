import Foundation
@testable import Termura
import XCTest

@MainActor
final class SessionInitTests: XCTestCase {
    func testControllerDoesNotStartSubscriptionsBeforeInject() async throws {
        let sessionID = SessionID()
        let engine = MockTerminalEngine()
        let sessionStore = MockSessionStore()
        let coordinator = AgentCoordinator(
            sessionID: sessionID,
            sessionStore: sessionStore,
            agentStateStore: MockAgentStateStore()
        )
        let outputStore = OutputStore(sessionID: sessionID)
        let tokenService = TokenCountingService()
        let processor = OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: tokenService
        )
        let controller = TerminalSessionController(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: InputModeController(),
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: SessionServices(),
            clock: TestClock(),
            notificationService: nil
        )

        XCTAssertNil(controller.streamTask)
        XCTAssertNil(controller.shellTask)

        let vm = TerminalViewModel(TerminalViewModel.Components(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: InputModeController(),
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: SessionServices()
        ))

        controller.inject(viewModel: vm)

        XCTAssertNotNil(controller.streamTask)
        XCTAssertNotNil(controller.shellTask)
    }
}
