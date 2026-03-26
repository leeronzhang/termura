import Foundation

/// Breakdown of estimated token counts by category (input, output, cached).
struct TokenEstimateBreakdown: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int

    var totalTokens: Int { inputTokens + outputTokens + cachedTokens }

    /// True when any breakdown category has a non-zero value.
    var hasBreakdown: Bool {
        inputTokens > 0 || outputTokens > 0 || cachedTokens > 0
    }

    static let zero = TokenEstimateBreakdown(inputTokens: 0, outputTokens: 0, cachedTokens: 0)
}
