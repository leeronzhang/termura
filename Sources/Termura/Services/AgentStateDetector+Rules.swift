import Foundation

// MARK: - Static pattern tables and rule evaluation

extension AgentStateDetector {
    static let launchPatterns: [(String, AgentType)] = [
        ("claude", .claudeCode),
        ("codex", .codex),
        ("aider", .aider),
        ("opencode", .openCode),
        ("oc ", .openCode),
        ("gemini", .gemini),
        ("pi ", .pi),
        ("pi-agent", .pi)
    ]

    /// Ordered rule table — evaluated top-to-bottom, first match wins; each rule is independently testable.
    static let statusRules: [StatusRule] = [
        // -- waitingInput: highest priority (user action required) --
        StatusRule(.waitingInput, .suffix("> "), label: "prompt-suffix"),
        StatusRule(.waitingInput, .suffix(">\n"), label: "prompt-suffix-nl"),
        StatusRule(.waitingInput, .contains("[Y/n]"), label: "confirm-yn"),
        StatusRule(.waitingInput, .contains("[y/N]"), label: "confirm-yN"),
        StatusRule(.waitingInput, .contains("Do you want to proceed"), label: "proceed-prompt"),
        StatusRule(.waitingInput, .contains("permission to"), label: "permission-prompt"),

        // -- error: second priority (needs attention) --
        StatusRule(.error, .containsCaseInsensitive("api error"), label: "api-error"),
        StatusRule(.error, .containsCaseInsensitive("rate limit"), label: "rate-limit"),
        StatusRule(.error, .containsCaseInsensitive("fatal:"), label: "fatal"),
        StatusRule(.error, .containsCaseInsensitive("panic:"), label: "panic"),
        StatusRule(.error, .containsCaseInsensitive("traceback"), label: "traceback"),
        StatusRule(.error, .containsCaseInsensitive("error:"), label: "error-colon"),

        // -- toolRunning: agent is executing a tool --
        StatusRule(.toolRunning, .contains("\u{23FA}"), label: "record-icon"),
        StatusRule(.toolRunning, .contains("Running:"), label: "running-label"),
        StatusRule(.toolRunning, .contains("Executing:"), label: "executing-label"),
        StatusRule(.toolRunning, .contains("Writing to"), label: "writing-to"),
        StatusRule(.toolRunning, .contains("tool_use"), label: "tool-use-tag"),
        StatusRule(.toolRunning, .contains("bash("), label: "bash-call"),

        // -- thinking: agent is generating --
        StatusRule(.thinking, .contains("Thinking"), label: "thinking-word"),
        // Removed ellipsis (\u{2026}) — too many false positives from npm/build output.
        StatusRule(.thinking, .contains("Generating"), label: "generating-word"),
        StatusRule(.thinking, .contains("\u{280B}"), label: "braille-spinner-1"),
        StatusRule(.thinking, .contains("\u{2819}"), label: "braille-spinner-2"),
        StatusRule(.thinking, .contains("\u{2839}"), label: "braille-spinner-3"),

        // -- completed: lowest priority --
        StatusRule(.completed, .contains("Task completed"), label: "task-completed"),
        StatusRule(.completed, .contains("Done!"), label: "done-bang"),
        StatusRule(.completed, .contains("finished"), label: "finished-word"),
        StatusRule(.completed, .contains("\u{2713}"), label: "checkmark")
    ]

    /// Pre-computed rule subsets per state — only rules leading to a valid transition are kept.
    static let reachableRules: [AgentStatus: [StatusRule]] = validTransitions.reduce(into: [:]) { map, entry in
        map[entry.key] = statusRules.filter { entry.value.contains($0.status) }
    }

    /// States that have at least one reachable rule using `.containsCaseInsensitive` matching.
    /// Pre-computed once so `analyzeOutput` can skip `lowercased()` allocation in states
    /// (e.g. `.completed`, `.error`) where no case-insensitive rule is reachable.
    static let statesNeedingLowercased: Set<AgentStatus> = reachableRules.reduce(into: []) { result, entry in
        let hasCaseInsensitive = entry.value.contains {
            if case .containsCaseInsensitive = $0.pattern { return true }
            return false
        }
        if hasCaseInsensitive { result.insert(entry.key) }
    }

    /// Evaluates reachable rules; one scalar walk gates all rare-char rules, skipping their contains() on ~95% of packets.
    /// Accepts any `StringProtocol` so callers can pass a `Substring` without materializing a `String` copy.
    func evaluateRules<S: StringProtocol>(_ text: S, lowercased lowercasedText: String) -> AgentStatus? {
        let rules = Self.reachableRules[currentStatus] ?? Self.statusRules
        let hasRareScalar = text.unicodeScalars.contains(where: StatusRule.agentRareScalars.contains)
        for rule in rules {
            if rule.isRareUnicodeRule && !hasRareScalar { continue }
            if rule.matchesFast(text, lowercased: lowercasedText) { return rule.status }
        }
        return nil
    }
}
