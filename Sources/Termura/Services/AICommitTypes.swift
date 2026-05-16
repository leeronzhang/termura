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
    /// (e.g. commit task left HEAD unchanged).
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

    /// Cancels the in-flight agent task, if any. The CLI runner translates
    /// Task cancellation into a SIGTERM on the child process. No-op when idle.
    @MainActor
    func cancel()

    /// Returns the first headless-capable agent whose CLI is on the user's PATH.
    /// Used as a fallback by `AIAgentDetector` so the Commit / Remote popovers
    /// can submit even when there is no active interactive session of the agent.
    /// Result is cached for the service's lifetime (PATH is stable per launch).
    @MainActor
    func probeAvailableHeadlessAgent() async -> AgentType?
}

/// Discrete AI git tasks the service dispatches. Replaces a stringly-typed
/// taskName so log lines + classifier branches can never typo apart.
enum AIAgentTaskKind: String, Sendable, Equatable {
    case commit
    case remoteSetup = "remote-setup"

    /// True when this task type runs `git commit` and therefore should treat
    /// pre-commit-hook stderr signals as a real failure.
    var invokesGitCommit: Bool {
        switch self {
        case .commit: true
        case .remoteSetup: false
        }
    }
}

/// Internal request bundle used by `AICommitService` to keep its dispatch
/// helper under the function-parameter-count budget.
struct AIAgentTaskRequest: Sendable {
    let kind: AIAgentTaskKind
    let prompt: String
    let projectRoot: URL
    let agent: AgentType
    let fromSessionLabel: String?
}
