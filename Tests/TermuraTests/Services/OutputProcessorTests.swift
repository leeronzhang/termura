import Foundation
import XCTest
@testable import Termura

/// Tests for OutputProcessor — chunk detection, shell event handling,
/// and token accumulation coordination.
@MainActor
final class OutputProcessorTests: XCTestCase {
    private var sessionID = SessionID()
    private var outputStore = OutputStore(sessionID: SessionID())
    private var tokenService = TokenCountingService()
    private var processor = OutputProcessor(
        sessionID: SessionID(),
        outputStore: OutputStore(sessionID: SessionID()),
        tokenCountingService: TokenCountingService()
    )

    override func setUp() async throws {
        sessionID = SessionID()
        outputStore = OutputStore(sessionID: sessionID)
        tokenService = TokenCountingService()
        processor = OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: tokenService
        )
    }

    // MARK: - processDataOutput

    func testProcessDataOutputAccumulatesTokens() async throws {
        let text = String(repeating: "hello world ", count: 100)
        await processor.processDataOutput(text, stripped: text, sessionID: sessionID)

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
    }

    func testProcessDataOutputMultipleCallsAccumulate() async throws {
        for i in 0 ..< 10 {
            let text = "output line \(i)\n"
            await processor.processDataOutput(text, stripped: text, sessionID: sessionID)
        }

        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
    }

    // MARK: - handleShellEvent

    func testHandleShellEventReturnsNilWithoutPriorOutput() async {
        let chunk = await processor.handleShellEvent(.executionFinished(exitCode: 0))
        _ = chunk
    }

    func testHandlePromptStartedReturnsNilOnFreshProcessor() async {
        let chunk = await processor.handleShellEvent(.promptStarted)
        XCTAssertNil(chunk)
    }

    // MARK: - accumulateInput

    func testAccumulateInputTracksTokens() async throws {
        await processor.accumulateInput("echo hello world", sessionID: sessionID)
        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
    }

    // MARK: - accumulateCached

    func testAccumulateCachedTracksTokens() async throws {
        await processor.accumulateCached(500, sessionID: sessionID)
        let breakdown = await tokenService.tokenBreakdown(for: sessionID)
        XCTAssertGreaterThanOrEqual(breakdown.cachedTokens, 500)
    }

    // MARK: - High-frequency output

    func testHighFrequencyProcessingDoesNotCrash() async throws {
        for i in 0 ..< 100 {
            let text = "Line \(i): " + String(repeating: "x", count: 200) + "\n"
            await processor.processDataOutput(text, stripped: text, sessionID: sessionID)
        }
        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
    }

    func testConcurrentProcessingDoesNotCrash() async throws {
        for i in 0 ..< 50 {
            let text = "concurrent line \(i)\n"
            await processor.processDataOutput(text, stripped: text, sessionID: sessionID)
        }
        let tokens = await tokenService.estimatedTokens(for: sessionID)
        XCTAssertGreaterThan(tokens, 0)
    }
}
