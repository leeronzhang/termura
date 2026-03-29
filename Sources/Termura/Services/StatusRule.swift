import Foundation

/// A single, independently testable detection rule.
/// Each rule maps a text pattern to an `AgentStatus`.
struct StatusRule: Sendable {
    let status: AgentStatus
    let pattern: Pattern
    /// Human-readable label for debugging and test identification.
    let label: String

    init(_ status: AgentStatus, _ pattern: Pattern, label: String) {
        self.status = status
        self.pattern = pattern
        self.label = label
    }

    /// Returns true if the text matches this rule's pattern.
    func matches(_ text: String) -> Bool {
        pattern.evaluate(text)
    }

    /// Fast-path variant that accepts a pre-lowercased copy of `text`.
    /// Avoids repeated lowercasing for `.containsCaseInsensitive` rules.
    func matchesFast(_ text: String, lowercased lowercasedText: String) -> Bool {
        pattern.evaluateFast(text, lowercased: lowercasedText)
    }

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
        /// For `.containsCaseInsensitive`, all needles in `statusRules` are lowercase literals,
        /// so `contains` on the pre-lowercased text is equivalent and avoids re-normalising.
        func evaluateFast(_ text: String, lowercased lowercasedText: String) -> Bool {
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
