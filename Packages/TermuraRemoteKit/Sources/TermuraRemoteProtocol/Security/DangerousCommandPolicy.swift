import Foundation

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
        self.compiledRules = Self.bestEffortCompile(rules: Rule.defaultRules)
    }

    public init(rules: [Rule]) throws {
        compiledRules = try rules.map { rule in
            let regex = try NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive])
            return (rule, regex)
        }
    }

    private static func bestEffortCompile(rules: [Rule]) -> [(rule: Rule, regex: NSRegularExpression)] {
        // Default rules are unit-tested to compile; this loop tolerates a future
        // regression by dropping the broken entry rather than crashing the app.
        // Custom callers wanting strict validation should use `init(rules:)`.
        var compiled: [(rule: Rule, regex: NSRegularExpression)] = []
        for rule in rules {
            do {
                let regex = try NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive])
                compiled.append((rule, regex))
            } catch {
                continue
            }
        }
        return compiled
    }

    public func evaluate(_ commandLine: String) -> Evaluation {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Evaluation(verdict: .safe, matchedReason: nil)
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for entry in compiledRules where entry.regex.firstMatch(in: trimmed, options: [], range: range) != nil {
            return Evaluation(verdict: entry.rule.verdict, matchedReason: entry.rule.reason)
        }
        return Evaluation(verdict: .safe, matchedReason: nil)
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
