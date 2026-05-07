import Foundation
@testable import Termura
import XCTest

@MainActor
final class TerminalViewModelAgentStateTests: XCTestCase {
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
        let coordinator = AgentCoordinator(sessionID: sessionID, sessionStore: sessionStore, agentStateStore: MockAgentStateStore())
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

    // MARK: - Refresh metadata

    func testRefreshMetadataUpdatesTokenCount() async {
        let vm = makeViewModel()
        await tokenService.accumulateOutput(for: sessionID, text: String(repeating: "a", count: 400))
        await vm.refreshMetadata()
        XCTAssertEqual(vm.currentMetadata.estimatedTokenCount, 100)
    }

    func testRefreshMetadataUpdatesCommandCount() async {
        let vm = makeViewModel()
        let chunk = OutputChunk(
            sessionID: sessionID,
            commandText: "ls",
            outputLines: ["output"],
            rawANSI: "output",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )
        outputStore.append(chunk)
        await vm.refreshMetadata()
        XCTAssertEqual(vm.currentMetadata.commandCount, 1)
    }

    func testRefreshMetadataPreservesWorkingDirectory() async {
        let vm = makeViewModel()
        vm.currentMetadata = SessionMetadata.empty(
            sessionID: sessionID,
            workingDirectory: "/custom/path"
        )
        await vm.refreshMetadata()
        XCTAssertEqual(vm.currentMetadata.workingDirectory, "/custom/path")
    }

    func testRefreshMetadataOverridesWorkingDirectory() async {
        let vm = makeViewModel()
        await vm.refreshMetadata(workingDirectory: "/new/path")
        XCTAssertEqual(vm.currentMetadata.workingDirectory, "/new/path")
    }

    // MARK: - Generate handoff guards

    func testGenerateHandoffWithoutServiceIsNoop() async {
        // sessionHandoffService is nil by default -> should return early.
        let vm = makeViewModel()
        let agentState = await vm.agentCoordinator.agentDetector.buildState()
        await vm.sessionServices.generateHandoffIfNeeded(
            session: nil,
            chunks: [],
            agentState: agentState,
            projectRoot: "/tmp/test-project"
        )
        // No crash, no side effects.
        XCTAssertNotNil(vm)
    }

    // MARK: - Update agent state

    func testUpdateAgentStateDoesNotCrashWithNoAgent() async {
        let vm = makeViewModel()
        // API split: compute off-actor then apply on main actor.
        if let result = await vm.agentCoordinator.computeAgentStateUpdate(
            tokenCountingService: tokenService
        ) {
            await vm.agentCoordinator.applyAgentStateUpdate(state: result.state, alert: result.alert)
        }
        // No agent detected -> buildState() returns nil -> computeAgentStateUpdate returns nil -> alert unchanged.
        XCTAssertNil(vm.contextWindowAlert)
    }
}
