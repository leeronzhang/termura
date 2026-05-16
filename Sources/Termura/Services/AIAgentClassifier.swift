import Foundation

/// Pattern matchers that translate raw CLI output into typed failure reasons.
/// Used by `AICommitService` for both commit and remote-setup pipelines.
///
/// All matchers anchor on stderr (not stdout) and require a non-zero exit
/// code where applicable. Stdout commonly contains the agent's own prose
/// describing what it did ("you can sign in with…", "this repo has no
/// pre-commit hook configured") — matching against stdout caused
/// successful runs to be reclassified as auth / hook failures.
enum AIAgentClassifier {
    /// Lower-cased substrings observed in stderr when the agent CLI reports
    /// it is not signed in. Patterns are narrow enough that they should not
    /// appear in benign explanatory output.
    static let authPatterns: [String] = [
        "not authenticated", "authentication required", "401 unauthorized",
        "please log in", "please login", "login required"
    ]

    /// Only treat as auth failure on non-zero exit. A successful agent run
    /// describing how to sign in elsewhere (e.g. in a commit message) must
    /// not be reclassified.
    static func matchesAuthFailure(stderr: String, exitCode: Int32) -> Bool {
        guard exitCode != 0 else { return false }
        let lc = stderr.lowercased()
        return authPatterns.contains { lc.contains($0) }
    }

    static func matchesBinaryMissing(stderr: String, exitCode: Int32) -> Bool {
        let lc = stderr.lowercased()
        return exitCode != 0
            && (lc.contains("command not found")
                || lc.contains("no such file or directory")
                || exitCode == 127)
    }

    /// Matches `git commit` hook failures echoed on stderr by the agent.
    /// Bare "pre-commit" appears in any repo that documents its hooks, so we
    /// also require a failure indicator (hook returned non-zero, "hook failed",
    /// or husky/lefthook's own failure banner) plus non-zero exit.
    static func matchesPreCommitHook(stderr: String, exitCode: Int32) -> Bool {
        guard exitCode != 0 else { return false }
        let lc = stderr.lowercased()
        return lc.contains("pre-commit hook")
            || lc.contains("hook failed")
            || (lc.contains("husky") && lc.contains("error"))
            || (lc.contains("lefthook") && lc.contains("error"))
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
}
