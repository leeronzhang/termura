import Foundation

/// Background actor that accumulates character counts per session
/// and provides heuristic token estimates (chars / divisor).
actor TokenCountingService {

    // MARK: - State

    private var charCounts: [SessionID: Int] = [:]
    private let divisor: Int

    // MARK: - Init

    init() {
        let rawDivisor = Int(AppConfig.AI.tokenEstimateDivisor)
        self.divisor = max(1, rawDivisor)
    }

    // MARK: - Public API

    /// Accumulate character count for a session from incoming text.
    func accumulate(for sessionID: SessionID, text: String) {
        charCounts[sessionID, default: 0] += text.count
    }

    /// Estimated token count for a session (charCount / divisor).
    func estimatedTokens(for sessionID: SessionID) -> Int {
        let chars = charCounts[sessionID] ?? 0
        return chars / divisor
    }

    /// Reset accumulated count for a session (e.g., on session close).
    func reset(for sessionID: SessionID) {
        charCounts.removeValue(forKey: sessionID)
    }
}
