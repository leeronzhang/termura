import Foundation
@testable import Termura
import XCTest

/// Contract tests for TokenCountingServiceProtocol and unit tests for
/// TokenCountingService behaviors not yet covered in TokenCountingServiceTests.swift.
///
/// Contract (mock vs real shared guarantees):
///   - estimatedTokens for a never-seen session returns 0 in both
///   - reset() clears the session's count to 0 in both
///
/// Real-only unit tests:
///   - CJK/Hiragana/Katakana characters are counted as 1 token each
///   - tokenBreakdown correctly separates input, output, and cached categories
///   - accumulateCached stores the count directly (not divided by asciiCharsPerToken)
///   - Input and output tokens are estimated through the heuristic
final class TokenCountingContractTests: XCTestCase {
    // MARK: - Contract: unknown session returns zero

    /// Both implementations must return 0 for a session that has never been touched.
    func testUnknownSessionReturnsZeroContract() async {
        let mock = MockTokenCountingService()
        let real = TokenCountingService()
        let sessionID = SessionID()

        let mockTokens = await mock.estimatedTokens(for: sessionID)
        let realTokens = await real.estimatedTokens(for: sessionID)

        XCTAssertEqual(mockTokens, 0)
        XCTAssertEqual(realTokens, 0)
        XCTAssertEqual(mockTokens, realTokens)
    }

    /// Both implementations must return the .zero breakdown for an unseen session.
    func testUnknownSessionBreakdownIsZeroContract() async {
        let mock = MockTokenCountingService()
        let real = TokenCountingService()
        let sessionID = SessionID()

        let mockBreakdown = await mock.tokenBreakdown(for: sessionID)
        let realBreakdown = await real.tokenBreakdown(for: sessionID)

        XCTAssertEqual(mockBreakdown.totalTokens, 0)
        XCTAssertEqual(realBreakdown.totalTokens, 0)
        XCTAssertFalse(mockBreakdown.hasBreakdown)
        XCTAssertFalse(realBreakdown.hasBreakdown)
    }

    // MARK: - Contract: reset clears tokens

    /// Both implementations must return 0 after reset(), regardless of prior state.
    func testResetClearsTokensContract() async {
        let mock = MockTokenCountingService()
        let real = TokenCountingService()
        let sessionID = SessionID()

        // Seed mock via stub; seed real via accumulation
        await mock.setStubbed(tokens: 1000, for: sessionID)
        await real.accumulateOutput(for: sessionID, text: String(repeating: "a", count: 400))

        await mock.reset(for: sessionID)
        await real.reset(for: sessionID)

        let mockTokens = await mock.estimatedTokens(for: sessionID)
        let realTokens = await real.estimatedTokens(for: sessionID)

        XCTAssertEqual(mockTokens, 0)
        XCTAssertEqual(realTokens, 0)
    }

    /// reset() for one session must not affect another session in either implementation.
    func testResetIsolationContract() async {
        let mock = MockTokenCountingService()
        let real = TokenCountingService()
        let sidA = SessionID()
        let sidB = SessionID()

        await mock.setStubbed(tokens: 500, for: sidA)
        await mock.setStubbed(tokens: 500, for: sidB)
        await real.accumulateOutput(for: sidA, text: String(repeating: "x", count: 2000))
        await real.accumulateOutput(for: sidB, text: String(repeating: "x", count: 2000))

        await mock.reset(for: sidA)
        await real.reset(for: sidA)

        let mockA = await mock.estimatedTokens(for: sidA)
        let realA = await real.estimatedTokens(for: sidA)
        let mockB = await mock.estimatedTokens(for: sidB)
        let realB = await real.estimatedTokens(for: sidB)
        XCTAssertEqual(mockA, 0)
        XCTAssertEqual(realA, 0)
        XCTAssertGreaterThan(mockB, 0)
        XCTAssertGreaterThan(realB, 0)
    }

    // MARK: - Real: CJK characters count as 1 token each

    /// CJK Unified Ideographs (U+4E00-U+9FFF) must each count as exactly 1 token.
    func testCJKUnifiedIdeographsAreOneTokenEach() async {
        let service = TokenCountingService()
        let sessionID = SessionID()
        // 8 CJK characters in the Basic Multilingual Plane
        let cjkText = "\u{4E2D}\u{6587}\u{6D4B}\u{8BD5}\u{5185}\u{5BB9}\u{6D4B}\u{8BD5}"
        await service.accumulateOutput(for: sessionID, text: cjkText)
        let tokens = await service.estimatedTokens(for: sessionID)
        XCTAssertEqual(tokens, 8)
    }

    /// Hiragana characters (U+3040-U+309F) must each count as exactly 1 token.
    func testHiraganaCharactersAreOneTokenEach() async {
        let service = TokenCountingService()
        let sessionID = SessionID()
        // 5 Hiragana characters: a, i, u, e, o
        let hiragana = "\u{3042}\u{3044}\u{3046}\u{3048}\u{304A}"
        await service.accumulateOutput(for: sessionID, text: hiragana)
        let tokens = await service.estimatedTokens(for: sessionID)
        XCTAssertEqual(tokens, 5)
    }

    /// Hangul Syllables (U+AC00-U+D7AF) must each count as exactly 1 token.
    func testHangulCharactersAreOneTokenEach() async {
        let service = TokenCountingService()
        let sessionID = SessionID()
        // 4 Hangul syllable characters
        let hangul = "\u{AC00}\u{AC01}\u{AC04}\u{AC07}"
        await service.accumulateOutput(for: sessionID, text: hangul)
        let tokens = await service.estimatedTokens(for: sessionID)
        XCTAssertEqual(tokens, 4)
    }

    // MARK: - Real: tokenBreakdown tracks all categories separately

    /// accumulateInput, accumulateOutput, and accumulateCached must each update their
    /// respective breakdown category independently.
    func testTokenBreakdownTracksAllCategoriesSeparately() async {
        let service = TokenCountingService()
        let sessionID = SessionID()

        // 400 ASCII = 100 tokens for input
        await service.accumulateInput(for: sessionID, text: String(repeating: "i", count: 400))
        // 800 ASCII = 200 tokens for output
        await service.accumulateOutput(for: sessionID, text: String(repeating: "o", count: 800))
        // 75 cached tokens stored directly
        await service.accumulateCached(for: sessionID, count: 75)

        let breakdown = await service.tokenBreakdown(for: sessionID)
        XCTAssertEqual(breakdown.inputTokens, 100)
        XCTAssertEqual(breakdown.outputTokens, 200)
        XCTAssertEqual(breakdown.cachedTokens, 75)
        XCTAssertEqual(breakdown.totalTokens, 375)

        let estimated = await service.estimatedTokens(for: sessionID)
        XCTAssertEqual(estimated, 375)
    }

    // MARK: - Real: accumulateCached stores count directly, not via heuristic

    /// Token counts parsed from agent output (e.g. "5000 tokens used") must be stored
    /// verbatim — not passed through the chars-per-token estimator.
    func testAccumulateCachedAddsDirectly() async {
        let service = TokenCountingService()
        let sessionID = SessionID()

        await service.accumulateCached(for: sessionID, count: 5000)

        let tokens = await service.estimatedTokens(for: sessionID)
        XCTAssertEqual(tokens, 5000)

        let breakdown = await service.tokenBreakdown(for: sessionID)
        XCTAssertEqual(breakdown.cachedTokens, 5000)
        XCTAssertEqual(breakdown.inputTokens, 0)
        XCTAssertEqual(breakdown.outputTokens, 0)
    }

    // MARK: - Real: multiple accumulate calls are additive per category

    /// Repeated calls to accumulateOutput must accumulate (not overwrite).
    func testMultipleAccumulationsAreAdditive() async {
        let service = TokenCountingService()
        let sessionID = SessionID()

        await service.accumulateOutput(for: sessionID, text: String(repeating: "a", count: 200))
        await service.accumulateOutput(for: sessionID, text: String(repeating: "a", count: 200))
        await service.accumulateCached(for: sessionID, count: 10)
        await service.accumulateCached(for: sessionID, count: 20)

        let breakdown = await service.tokenBreakdown(for: sessionID)
        XCTAssertEqual(breakdown.outputTokens, 100) // 400 ASCII / 4
        XCTAssertEqual(breakdown.cachedTokens, 30) // 10 + 20
    }
}
