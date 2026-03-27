import Foundation
import XCTest
@testable import Termura

/// Tests for TerminalViewModel.handleDataOutput — high-frequency scenarios,
/// concurrent processing, and token accumulation under load.
@MainActor
final class TerminalViewModelDataOutputTests: XCTestCase {
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

    // MARK: - High-frequency data events

    func testRapidDataEventsAccumulateTokens() async throws {
        let vm = makeViewModel()
        for i in 0 ..< 20 {
            let text = "Line \(i): " + String(repeating: "x", count: 100) + "\n"
            await engine.emit(.data(Data(text.utf8)))
        }
        try await yieldForDuration(seconds: 0.5)

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
        _ = vm
    }

    func testDataEventWithInvalidUTF8IsIgnored() async throws {
        let vm = makeViewModel()
        let invalidData = Data([0xFF, 0xFE, 0x80, 0x81])
        await engine.emit(.data(invalidData))
        try await yieldForDuration(seconds: 0.2)

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertEqual(tokens, 0)
        _ = vm
    }

    func testEmptyDataEventIsIgnored() async throws {
        let vm = makeViewModel()
        await engine.emit(.data(Data()))
        try await yieldForDuration(seconds: 0.1)

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertEqual(tokens, 0)
        _ = vm
    }

    // MARK: - Agent detection from output

    func testAgentDetectedFromDataOutput() async throws {
        let vm = makeViewModel()
        let text = "Welcome to Claude Code v1.0.0"
        await engine.emit(.data(Data(text.utf8)))
        try await yieldForDuration(seconds: 0.3)

        XCTAssertTrue(vm.agentCoordinator.hasDetectedAgentFromOutput)
        XCTAssertEqual(vm.agentCoordinator.lastDetectedAgentType, .claudeCode)
    }

    // MARK: - Metadata refresh from data output

    func testDataOutputTriggersMetadataRefresh() async throws {
        let vm = makeViewModel()
        let text = String(repeating: "output data ", count: 50)
        await engine.emit(.data(Data(text.utf8)))
        try await yieldForDuration(seconds: 0.3)

        XCTAssertGreaterThan(vm.currentMetadata.estimatedTokenCount, 0)
    }

    // MARK: - Shell event + data interleaving

    func testShellEventInterleavedWithDataDoesNotCrash() async throws {
        let vm = makeViewModel()

        for i in 0 ..< 10 {
            let text = "cmd output \(i)\n"
            await engine.emit(.data(Data(text.utf8)))
            if i % 3 == 0 {
                await engine.emitShellEvent(.promptStarted)
            }
            if i % 5 == 0 {
                await engine.emitShellEvent(.executionStarted)
            }
        }
        try await yieldForDuration(seconds: 0.3)

        XCTAssertNotNil(vm)
    }

    // MARK: - Multiple sends interleaved with data

    func testSendAndReceiveInterleaved() async throws {
        let vm = makeViewModel()

        vm.send("echo hello")
        await engine.emit(.data(Data("hello\n".utf8)))
        vm.send("ls -la")

        try await yieldForDuration(seconds: 0.2)

        let sent = await engine.sentTexts
        XCTAssertTrue(sent.contains("echo hello"))
        XCTAssertTrue(sent.contains("ls -la"))
    }

    // MARK: - Process exit after data

    func testProcessExitAfterDataDoesNotCrash() async throws {
        let vm = makeViewModel()
        await engine.emit(.data(Data("final output\n".utf8)))
        await engine.emit(.processExited(0))
        try await yieldForDuration(seconds: 0.2)

        XCTAssertNotNil(vm)
    }

    // MARK: - Large output burst

    func testLargeOutputBurstDoesNotExceedCapacity() async throws {
        let vm = makeViewModel()
        let largeText = String(repeating: "x", count: 50_000)
        await engine.emit(.data(Data(largeText.utf8)))
        try await yieldForDuration(seconds: 0.5)

        XCTAssertLessThanOrEqual(
            outputStore.chunks.count,
            AppConfig.Output.maxChunksPerSession
        )
        _ = vm
    }
}
