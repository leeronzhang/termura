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
    }
}
