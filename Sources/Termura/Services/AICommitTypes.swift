import Foundation

/// Outcome of an AI agent task (commit, remote setup, etc.).
/// Named for historical reasons — the type is shared across all delegated AI git tasks.
enum AICommitResult: Sendable, Equatable {
    /// AI ran the task to completion. `summary` is a short human-readable result line
    /// (commit subject, "remote configured", etc.) for the toast.
    case success(summary: String)
    case failure(reason: AICommitFailureReason, message: String)
}

/// Categorized failure mode. Drives the toast wording so users get actionable text.
enum AICommitFailureReason: String, Sendable, Equatable {
    /// Agent CLI binary could not be found in PATH.
    case agentNotFound
    /// CLI ran but reported it is not authenticated / needs login.
    case authRequired
    /// Agent's headless mode is not supported in this build.
    case agentUnsupported
    /// Agent exited 0 but the verification step decided no work happened
    /// (e.g. commit task left the working tree dirty).
    case agentDeclined
    /// Hard timeout fired before the agent returned.
    case timedOut
    /// A git pre-commit hook (husky / lefthook / etc.) blocked the commit.
    case gitHookFailed
    /// Catch-all for non-zero exits without a more specific match.
    case other
}

/// Backwards-compat alias for the success(commitSubject:) call site shape.
extension AICommitResult {
    static func success(commitSubject: String) -> AICommitResult {
        .success(summary: commitSubject)
    }
}

protocol AICommitServiceProtocol: AnyObject, Sendable {
    @MainActor var isBusy: Bool { get }
    @MainActor var lastResult: AICommitResult? { get }

    @MainActor
    func commit(note: String?,
                projectRoot: URL,
                agent: AgentType,
                fromSessionLabel: String?) async -> AICommitResult

    @MainActor
    func setupRemote(note: String?,
                     projectRoot: URL,
                     agent: AgentType,
                     fromSessionLabel: String?) async -> AICommitResult
}

/// Internal request bundle used by `AICommitService` to keep its dispatch
/// helper under the function-parameter-count budget.
struct AIAgentTaskRequest: Sendable {
    let taskName: String
    let prompt: String
    let projectRoot: URL
    let agent: AgentType
    let fromSessionLabel: String?
    /// True when the pre-commit hook stderr keyword should be treated as a hook failure.
    /// Only relevant for tasks that actually invoke `git commit`.
    let preCommitHookCheck: Bool
}
