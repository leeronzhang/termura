import Foundation
import XCTest
@testable import Termura

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

    // MARK: - Refresh metadata

    func testRefreshMetadataUpdatesTokenCount() async {
        let vm = makeViewModel()
        await tokenService.accumulate(for: sessionID, text: String(repeating: "a", count: 400))
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
        vm.sessionServices.generateHandoffIfNeeded(
            session: nil,
            chunks: [],
            agentState: agentState,
            handoffService: nil,
            taskExecutor: BoundedTaskExecutor(maxConcurrent: 1)
        )
        // No crash, no side effects.
        XCTAssertNotNil(vm)
    }

    // MARK: - Update agent state

    func testUpdateAgentStateDoesNotCrashWithNoAgent() async {
        let vm = makeViewModel()
        await vm.agentCoordinator.updateAgentState(
            tokenCountingService: tokenService,
            sessionID: sessionID
        )
        // No agent detected -> agentDetector.buildState() returns nil -> early return.
        XCTAssertNil(vm.contextWindowAlert)
    }
}
