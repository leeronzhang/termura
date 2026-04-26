import Foundation

/// Pattern matchers that translate raw CLI output into typed failure reasons.
/// Used by `AICommitService` for both commit and remote-setup pipelines.
/// The patterns are heuristic — review periodically against current Claude Code / Codex output.
enum AIAgentClassifier {
    /// Lower-cased substrings observed when the agent CLI reports it is not signed in.
    /// Sourced from Claude Code (~v0.x) and Codex CLI as of plan time.
    static let authPatterns: [String] = [
        "please run", "please log in", "not authenticated", "unauthorized",
        "auth required", "login required", "sign in"
    ]

    static func matchesAuthFailure(stderr: String, stdout: String) -> Bool {
        let combined = (stderr + "\n" + stdout).lowercased()
        return authPatterns.contains { combined.contains($0) }
    }

    static func matchesBinaryMissing(stderr: String, exitCode: Int32) -> Bool {
        let lc = stderr.lowercased()
        return exitCode != 0
            && (lc.contains("command not found")
                || lc.contains("no such file or directory")
                || exitCode == 127)
    }

    static func matchesPreCommitHook(stderr: String, stdout: String) -> Bool {
        let combined = (stderr + "\n" + stdout).lowercased()
        return combined.contains("pre-commit")
            || combined.contains("husky")
            || combined.contains("lefthook")
    }

    /// First non-empty line of stderr (or stdout fallback), capped to ~120 chars.
    static func shortErrorSnippet(output: CLIProcessOutput) -> String {
        let source = output.stderr.isEmpty ? output.stdout : output.stderr
        let trimmedLine = source
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "AI task failed (exit \(output.exitCode))"
        return trimmedLine.count > 120 ? String(trimmedLine.prefix(120)) + "…" : trimmedLine
    }

    /// Best-effort extraction of a commit subject from agent stdout. Looks for the
    /// `[branch hash] subject` line that `git commit` echoes.
    static func commitSubject(from output: CLIProcessOutput) -> String? {
        let lines = output.stdout.split(separator: "\n").map(String.init)
        for line in lines.reversed() {
            if let range = line.range(of: #"\[\w+ [0-9a-f]{7,}\] (.+)$"#, options: .regularExpression) {
                let captured = String(line[range])
                if let subjectStart = captured.range(of: "] ") {
                    return String(captured[subjectStart.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
}
