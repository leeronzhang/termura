import Foundation

/// Static prompt templates handed to the user's CLI agent for delegated git tasks.
/// Kept separate from the orchestrator so prompt iteration doesn't churn service code.
enum AICommitPrompts {
    static func commit(note: String?) -> String {
        var prompt = """
        Review the current uncommitted changes in this Git repository, \
        generate a clear, focused commit message, and run `git commit` to commit them.

        Constraints:
        - Do not push. Local commit only.
        - Prefer a single commit unless the user note below requests otherwise.
        - Match the existing project commit style if discoverable from `git log`.
        """
        if let trimmed = trimOrNil(note) {
            prompt += "\n\nUser context:\n\(trimmed)"
        }
        return prompt
    }

    static func remoteSetup(note: String?) -> String {
        var prompt = """
        Configure the Git remote for this repository as the user describes below. \
        Run the necessary `git remote` commands (add / set-url / remove) and verify with \
        `git remote -v`. If the user wants a new remote on a hosted provider, use `gh repo create` \
        (or the equivalent CLI) only if it is already authenticated; otherwise stop and report \
        that authentication is needed.

        Constraints:
        - Do not push. Configuration only.
        - Do not commit any files.
        - Echo the final `git remote -v` output before returning.

        User request:
        """
        if let trimmed = trimOrNil(note) {
            prompt += "\n\(trimmed)"
        } else {
            prompt += "\nSet up a sensible remote for this project."
        }
        return prompt
    }

    private static func trimOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
