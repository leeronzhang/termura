import Foundation

/// Test double for `TokenCountingServiceProtocol`.
actor MockTokenCountingService: TokenCountingServiceProtocol {
    var stubbedTokens: [SessionID: Int] = [:]
    var stubbedBreakdowns: [SessionID: TokenEstimateBreakdown] = [:]
    var accumulateCallCount = 0
    var accumulateInputCallCount = 0
    var accumulateOutputCallCount = 0
    var accumulateCachedCallCount = 0
    var resetCallCount = 0

    func accumulate(for sessionID: SessionID, text: String) {
        accumulateCallCount += 1
        let current = stubbedTokens[sessionID] ?? 0
        stubbedTokens[sessionID] = current + text.count / 4
    }

    func accumulateInput(for sessionID: SessionID, text: String) {
        accumulateInputCallCount += 1
    }

    func accumulateOutput(for sessionID: SessionID, text: String) {
        accumulateOutputCallCount += 1
    }

    func accumulateCached(for sessionID: SessionID, count: Int) {
        accumulateCachedCallCount += 1
    }

    func estimatedTokens(for sessionID: SessionID) -> Int {
        stubbedTokens[sessionID] ?? 0
    }

    func tokenBreakdown(for sessionID: SessionID) -> TokenEstimateBreakdown {
        stubbedBreakdowns[sessionID] ?? .zero
    }

    func reset(for sessionID: SessionID) {
        resetCallCount += 1
        stubbedTokens.removeValue(forKey: sessionID)
        stubbedBreakdowns.removeValue(forKey: sessionID)
    }
}
