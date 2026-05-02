import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.remote", category: "DangerousCommandPolicy")

public struct DangerousCommandPolicy: Sendable {
    public struct Rule: Sendable, Equatable {
        public let pattern: String
        public let verdict: SafetyVerdict
        public let reason: String

        public init(pattern: String, verdict: SafetyVerdict, reason: String) {
            self.pattern = pattern
            self.verdict = verdict
            self.reason = reason
        }
    }

    public struct Evaluation: Sendable, Equatable {
        public let verdict: SafetyVerdict
        public let matchedReason: String?

        public init(verdict: SafetyVerdict, matchedReason: String?) {
            self.verdict = verdict
            self.matchedReason = matchedReason
        }
    }

    private let compiledRules: [(rule: Rule, regex: NSRegularExpression)]

    public init() {
        compiledRules = Self.bestEffortCompile(rules: Rule.defaultRules)
    }

    public init(rules: [Rule]) throws {
        compiledRules = try rules.map { rule in
            let regex = try NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive])
            return (rule, regex)
        }
    }

    private static func bestEffortCompile(rules: [Rule]) -> [(rule: Rule, regex: NSRegularExpression)] {
        // Default rules are unit-tested to compile. A future regression
        // that lands a broken pattern shouldn't crash the app, but it
        // also shouldn't be invisible: dropping a safety rule weakens
        // the user's protection (`fork bomb`, `sudo`, `rm -rf`, etc.),
        // so we surface the failure at `.fault` level — the strongest
        // OSLog severity short of crashing — and keep going. Custom
        // callers wanting strict validation use `init(rules:)`.
        var compiled: [(rule: Rule, regex: NSRegularExpression)] = []
        for rule in rules {
            do {
                let regex = try NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive])
                compiled.append((rule, regex))
            } catch {
                let reasonForLog = rule.reason
                let errorForLog = error.localizedDescription
                logger.fault(
                    """
                    Dropping dangerous-command rule \(reasonForLog, privacy: .public): \
                    regex compile failed (\(errorForLog, privacy: .public)). \
                    Safety coverage is reduced until this is fixed.
                    """
                )
                continue
            }
        }
        return compiled
    }

    /// Wave 3 — verdict picked by **strictest match**, not by rule
    /// declaration order. Pre-Wave-3 the loop returned the first match
    /// it found, so a `.requiresConfirmation` rule sitting above a
    /// matching `.blocked` rule (or a future overlap a custom rule set
    /// introduces) would silently downgrade the verdict. The default
    /// rule set has no overlap, so behaviour is unchanged on the
    /// happy path; the fix is correctness for arbitrary rule orderings.
    /// `matchedReason` aggregates every contributing rule when more
    /// than one fires, so the audit trail and user-facing message
    /// keep all relevant context.
    public func evaluate(_ commandLine: String) -> Evaluation {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Evaluation(verdict: .safe, matchedReason: nil)
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        var matchedReasons: [SafetyVerdict: [String]] = [:]
        for entry in compiledRules
            where entry.regex.firstMatch(in: trimmed, options: [], range: range) != nil {
            matchedReasons[entry.rule.verdict, default: []].append(entry.rule.reason)
        }
        guard let strictest = matchedReasons.keys.max(by: { Self.severity(of: $0) < Self.severity(of: $1) }) else {
            return Evaluation(verdict: .safe, matchedReason: nil)
        }
        let reasons = matchedReasons[strictest, default: []]
        let combined = reasons.isEmpty ? nil : reasons.joined(separator: "; ")
        return Evaluation(verdict: strictest, matchedReason: combined)
    }

    /// Total order on `SafetyVerdict` by strictness. `.blocked` >
    /// `.requiresConfirmation` > `.safe`. Internal so the evaluator
    /// can pick the strictest verdict among matching rules without
    /// teaching `SafetyVerdict` itself a `Comparable` conformance —
    /// the wire enum stays free of UI-policy ordering.
    private static func severity(of verdict: SafetyVerdict) -> Int {
        switch verdict {
        case .safe: 0
        case .requiresConfirmation: 1
        case .blocked: 2
        }
    }
}

public extension DangerousCommandPolicy.Rule {
    static let defaultRules: [DangerousCommandPolicy.Rule] = [
        .init(pattern: #"(^|\s|;|&&|\|\|)rm\s+(-[a-zA-Z]*[rRfF]+[a-zA-Z]*|--recursive|--force)"#,
              verdict: .requiresConfirmation,
              reason: "rm with recursive/force flag"),
        .init(pattern: #"(^|\s|;|&&|\|\|)sudo(\s|$)"#,
              verdict: .requiresConfirmation,
              reason: "sudo elevation"),
        .init(pattern: #"\|\s*(bash|sh|zsh|fish)(\s|$)"#,
              verdict: .requiresConfirmation,
              reason: "pipe to shell interpreter"),
        .init(pattern: #"(curl|wget)\s[^|]*\|\s*(bash|sh|zsh)"#,
              verdict: .requiresConfirmation,
              reason: "curl/wget piped to shell"),
        .init(pattern: #"(^|\s|;|&&|\|\|)dd\s+(if=|of=)"#,
              verdict: .requiresConfirmation,
              reason: "dd raw disk write"),
        .init(pattern: #"(^|\s|;|&&|\|\|)mkfs\.[a-z0-9]+(\s|$)"#,
              verdict: .requiresConfirmation,
              reason: "mkfs filesystem creation"),
        .init(pattern: #"(^|\s|;|&&|\|\|)(shutdown|reboot|halt|poweroff)(\s|$)"#,
              verdict: .requiresConfirmation,
              reason: "system power command"),
        .init(pattern: #"(^|\s|;|&&|\|\|)chmod\s+[0-7]*7[0-7]*7\s+/"#,
              verdict: .requiresConfirmation,
              reason: "chmod world-writable on root path"),
        .init(pattern: #"(^|\s|;|&&|\|\|)chown\s+root[:\s]"#,
              verdict: .requiresConfirmation,
              reason: "chown root"),
        .init(pattern: #">\s*/(dev|etc|System|usr|bin|sbin|var/log)(/|\s|$)"#,
              verdict: .requiresConfirmation,
              reason: "redirect into protected system path"),
        .init(pattern: #":\s*\(\s*\)\s*\{\s*:\s*\|\s*:\s*&\s*\}"#,
              verdict: .blocked,
              reason: "fork bomb"),
        .init(pattern: #"(^|\s|;|&&|\|\|)diskutil\s+(eraseDisk|eraseVolume|secureErase)"#,
              verdict: .requiresConfirmation,
              reason: "diskutil erase"),
        .init(pattern: #"(^|\s|;|&&|\|\|)kill(all)?\s+-9"#,
              verdict: .requiresConfirmation,
              reason: "kill -9 force termination"),
        .init(pattern: #"launchctl\s+(remove|unload|bootout)"#,
              verdict: .requiresConfirmation,
              reason: "launchctl service removal"),
        .init(pattern: #"git\s+push\s+(--force|-f)(\s|$)"#,
              verdict: .requiresConfirmation,
              reason: "git push --force")
    ]
}
