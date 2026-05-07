import Foundation
@testable import Termura
import XCTest

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

    // MARK: - High-frequency data events

    func testRapidDataEventsAccumulateTokens() async throws {
        let vm = makeViewModel()
        let tokenService = tokenService
        let sessionID = sessionID
        for i in 0 ..< 20 {
            let text = "Line \(i): " + String(repeating: "x", count: 100) + "\n"
            engine.emit(.data(Data(text.utf8)))
        }
        try await waitUntil {
            await tokenService.estimatedTokens(for: sessionID) > 0
        }

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
        _ = vm
    }

    /// Non-UTF-8 bytes are decoded via ISO Latin-1 fallback (not silently dropped).
    /// This test verifies the fallback path is exercised and produces non-zero tokens.
    func testDataEventWithInvalidUTF8UsesLatin1Fallback() async throws {
        let vm = makeViewModel()
        let invalidData = Data([0xFF, 0xFE, 0x80, 0x81])
        let tokenService = tokenService
        let sessionID = sessionID
        engine.emit(.data(invalidData))
        try await waitUntil {
            await tokenService.estimatedTokens(for: sessionID) > 0
        }

        // Latin-1 decodes all byte values; tokens > 0 confirms the fallback path ran.
        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
        _ = vm
    }

    func testEmptyDataEventIsIgnored() async throws {
        let vm = makeViewModel()
        engine.emit(.data(Data()))
        try await yieldForDuration(seconds: 0.1)

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertEqual(tokens, 0)
        _ = vm
    }

    // MARK: - Agent detection from output

    func testAgentDetectedFromDataOutput() async throws {
        let vm = makeViewModel()
        let text = "Welcome to Claude Code v1.0.0"
        engine.emit(.data(Data(text.utf8)))
        try await waitUntil {
            await vm.agentCoordinator.hasDetectedAgentFromOutput
        }

        let detected = await vm.agentCoordinator.hasDetectedAgentFromOutput
        let agentType = await vm.agentCoordinator.lastDetectedAgentType
        XCTAssertTrue(detected)
        XCTAssertEqual(agentType, .claudeCode)
    }

    // MARK: - Metadata refresh from data output

    func testDataOutputTriggersMetadataRefresh() async throws {
        let vm = makeViewModel()
        let text = String(repeating: "output data ", count: 50)
        engine.emit(.data(Data(text.utf8)))
        try await waitUntil { vm.currentMetadata.estimatedTokenCount > 0 }

        XCTAssertGreaterThan(vm.currentMetadata.estimatedTokenCount, 0)
    }

    // MARK: - Shell event + data interleaving

    func testShellEventInterleavedWithDataDoesNotCrash() async throws {
        let vm = makeViewModel()
        let tokenService = tokenService
        let sessionID = sessionID

        for i in 0 ..< 10 {
            let text = "cmd output \(i)\n"
            engine.emit(.data(Data(text.utf8)))
            if i % 3 == 0 {
                engine.emitShellEvent(.promptStarted)
            }
            if i % 5 == 0 {
                engine.emitShellEvent(.executionStarted)
            }
        }
        try await waitUntil {
            await tokenService.estimatedTokens(for: sessionID) > 0
        }

        XCTAssertNotNil(vm)
    }

    // MARK: - Multiple sends interleaved with data

    func testSendAndReceiveInterleaved() async throws {
        let vm = makeViewModel()
        let engine = engine

        vm.send("echo hello")
        engine.emit(.data(Data("hello\n".utf8)))
        vm.send("ls -la")

        try await waitUntil { engine.sentTexts.count == 2 }

        let sent = engine.sentTexts
        XCTAssertTrue(sent.contains("echo hello"))
        XCTAssertTrue(sent.contains("ls -la"))
    }

    // MARK: - Process exit after data

    func testProcessExitAfterDataDoesNotCrash() async throws {
        let vm = makeViewModel()
        let tokenService = tokenService
        let sessionID = sessionID
        engine.emit(.data(Data("final output\n".utf8)))
        engine.emit(.processExited(0))
        try await waitUntil {
            await tokenService.estimatedTokens(for: sessionID) > 0
        }

        XCTAssertNotNil(vm)
    }

    // MARK: - Large output burst

    func testLargeOutputBurstDoesNotExceedCapacity() async throws {
        let vm = makeViewModel()
        let largeText = String(repeating: "x", count: 50000)
        let tokenService = tokenService
        let sessionID = sessionID
        let outputStore = outputStore
        engine.emit(.data(Data(largeText.utf8)))
        try await waitUntil {
            await tokenService.estimatedTokens(for: sessionID) > 0
        }

        XCTAssertLessThanOrEqual(
            outputStore.chunks.count,
            AppConfig.Output.maxChunksPerSession
        )
        _ = vm
    }
}
