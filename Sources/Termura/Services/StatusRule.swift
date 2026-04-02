import Foundation

/// A single, independently testable detection rule.
/// Each rule maps a text pattern to an `AgentStatus`.
struct StatusRule: Sendable {
    let status: AgentStatus
    let pattern: Pattern
    /// Human-readable label for debugging and test identification.
    let label: String
    /// True when this rule's needle is a single rare Unicode scalar that can be gated
    /// behind the shared `agentRareScalars` pre-scan in `AgentStateDetector.evaluateRules`.
    /// Stored once at init — `pattern` is immutable so the result never changes.
    let isRareUnicodeRule: Bool

    init(_ status: AgentStatus, _ pattern: Pattern, label: String) {
        self.status = status
        self.pattern = pattern
        self.label = label
        if case let .contains(needle) = pattern,
           needle.unicodeScalars.count == 1,
           let scalar = needle.unicodeScalars.first {
            isRareUnicodeRule = StatusRule.agentRareScalars.contains(scalar)
        } else {
            isRareUnicodeRule = false
        }
    }

    /// Returns true if the text matches this rule's pattern.
    func matches(_ text: String) -> Bool {
        pattern.evaluate(text)
    }

    /// Fast-path variant that accepts any `StringProtocol` value (e.g. `Substring`) so callers
    /// can avoid materializing a `String` copy. Also accepts a pre-lowercased `String` copy
    /// to avoid repeated lowercasing for `.containsCaseInsensitive` rules.
    func matchesFast(_ text: some StringProtocol, lowercased lowercasedText: String) -> Bool {
        pattern.evaluateFast(text, lowercased: lowercasedText)
    }

    /// Unicode scalars that appear exclusively in agent output and never in ordinary
    /// shell or compiler output. A single `unicodeScalars.contains(where:)` walk gates
    /// all rules whose needle is one of these scalars, replacing N separate
    /// `String.contains()` calls with one O(n) scalar scan.
    static let agentRareScalars: Set<Unicode.Scalar> = [
        "\u{23FA}", // record indicator  (toolRunning)
        "\u{2713}", // check mark        (completed)
        "\u{280B}", // braille spinner   (thinking)
        "\u{2819}", // braille spinner   (thinking)
        "\u{2839}" // braille spinner   (thinking)
    ]

    /// Pattern types for flexible matching.
    enum Pattern: Sendable {
        case contains(String)
        case containsCaseInsensitive(String)
        case suffix(String)

        func evaluate(_ text: String) -> Bool {
            switch self {
            case let .contains(needle):
                text.contains(needle)
            case let .containsCaseInsensitive(needle):
                text.localizedCaseInsensitiveContains(needle)
            case let .suffix(needle):
                text.hasSuffix(needle)
            }
        }

        /// Fast-path evaluation using a caller-supplied pre-lowercased copy of `text`.
        /// Accepts any `StringProtocol` value so callers can pass a `Substring` without
        /// materializing a `String` copy first. For `.containsCaseInsensitive`, all needles
        /// in `statusRules` are lowercase literals, so `contains` on the pre-lowercased text
        /// is equivalent and avoids re-normalising.
        func evaluateFast(_ text: some StringProtocol, lowercased lowercasedText: String) -> Bool {
            switch self {
            case let .contains(needle):
                return text.contains(needle)
            case let .containsCaseInsensitive(needle):
                // Requires needle to be lowercase. Asserted in debug builds.
                assert(needle == needle.lowercased(), "containsCaseInsensitive needle must be lowercase")
                return lowercasedText.contains(needle)
            case let .suffix(needle):
                return text.hasSuffix(needle)
            }
        }
    }
}
