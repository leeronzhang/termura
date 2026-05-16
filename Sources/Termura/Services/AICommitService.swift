import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AICommitService")

@MainActor
@Observable
final class AICommitService: AICommitServiceProtocol {
    /// True while any AI agent task (commit, remote setup, …) is running.
    /// Concurrent AI git tasks are not meaningful for a single repo, so a single
    /// flag gates all entrypoints.
    private(set) var isBusy = false
    /// Last terminal outcome of a task the service actually executed. Rejections
    /// (e.g. "another task already in progress") do NOT update this — they're
    /// not results, they're refusals at the entry gate. Inspect `isBusy` to
    /// detect a rejection-eligible state instead.
    private(set) var lastResult: AICommitResult?

    // Internal (not private) so `AICommitService+PathProbe.swift` extension can
    // reach `runner` and `shellEnv` for the `which <cmd>` probe. Actor / @MainActor
    // isolation already enforces single-threaded access; intra-target visibility
    // adds no concurrency risk.
    @ObservationIgnored let runner: any CLIProcessRunnerProtocol
    @ObservationIgnored let shellEnv: any UserShellEnvironmentProtocol
    @ObservationIgnored private let gitService: any GitServiceProtocol
    @ObservationIgnored private let timeout: Duration
    /// Handle on the in-flight task so `cancel()` can tear it down. Stored on
    /// the @MainActor type so observers and the cancel call are isolation-safe.
    @ObservationIgnored private var inflightTask: Task<AICommitResult, Never>?
    /// PATH-probe cache. Boxed `Optional` so non-nil = "we've probed",
    /// regardless of outcome. Wired by `AICommitService+PathProbe.swift`.
    @ObservationIgnored var cachedHeadlessAgent: CachedHeadlessAgent?

    /// Boxes the optional probe result so `cachedHeadlessAgent != nil` means
    /// "we've probed", regardless of whether anything was found.
    struct CachedHeadlessAgent {
        let value: AgentType?
    }

    init(
        runner: any CLIProcessRunnerProtocol,
        shellEnv: any UserShellEnvironmentProtocol,
        gitService: any GitServiceProtocol,
        timeout: Duration = AppConfig.AICommit.commandTimeout
    ) {
        self.runner = runner
        self.shellEnv = shellEnv
        self.gitService = gitService
        self.timeout = timeout
    }

    // MARK: - Public entry points

    func commit(
        note: String?,
        projectRoot: URL,
        agent: AgentType,
        fromSessionLabel: String?
    ) async -> AICommitResult {
        let request = AIAgentTaskRequest(
            kind: .commit,
            prompt: AICommitPrompts.commit(note: note),
            projectRoot: projectRoot,
            agent: agent,
            fromSessionLabel: fromSessionLabel
        )
        let preSHA = await Self.snapshotHEAD(projectRoot: projectRoot, gitService: gitService)
        return await runAgentTask(request) { [gitService] _ in
            let postSHA = await Self.snapshotHEAD(projectRoot: projectRoot, gitService: gitService)
            guard let postSHA, postSHA != preSHA else {
                return .failure(
                    reason: .agentDeclined,
                    message: "\(agent.displayName) did not commit. See terminal for details."
                )
            }
            let subject = await Self.fetchCommitSubject(projectRoot: projectRoot, gitService: gitService) ?? "Committed"
            return .success(summary: subject)
        }
    }

    func setupRemote(
        note: String?,
        projectRoot: URL,
        agent: AgentType,
        fromSessionLabel: String?
    ) async -> AICommitResult {
        let request = AIAgentTaskRequest(
            kind: .remoteSetup,
            prompt: AICommitPrompts.remoteSetup(note: note),
            projectRoot: projectRoot,
            agent: agent,
            fromSessionLabel: fromSessionLabel
        )
        return await runAgentTask(request) { _ in
            // Exit 0 + no auth/binary failure is enough. The agent has its own tool access;
            // if it succeeded, trust the exit code.
            .success(summary: "Remote configured")
        }
    }

    /// Tears down the currently-running agent task, if any. Propagates Task
    /// cancellation to `CLIProcessRunner`, which terminates the child process
    /// via its `withTaskCancellationHandler`. Safe to call when idle (no-op).
    func cancel() {
        inflightTask?.cancel()
    }

    // MARK: - Shared task runner

    /// Runs the request's prompt headless on its agent, classifies common failures,
    /// and on a clean exit hands the raw output to `successHandler`. Result-writing
    /// rule: `lastResult` is updated on every path that actually invoked the agent
    /// (including unsupported / launch failures). The single rejection path
    /// (`isBusy == true` at entry) does not touch `lastResult`.
    private func runAgentTask(
        _ request: AIAgentTaskRequest,
        successHandler: @escaping (CLIProcessOutput) async -> AICommitResult
    ) async -> AICommitResult {
        guard !isBusy else {
            return .failure(reason: .other, message: "Another AI task is already in progress")
        }
        guard let args = request.agent.headlessArgs(prompt: request.prompt) else {
            let result = AICommitResult.failure(
                reason: .agentUnsupported,
                message: "\(request.agent.displayName) headless mode not supported"
            )
            lastResult = result
            return result
        }

        isBusy = true
        logTaskStart(request)
        // WHY: storing the inflight Task lets `cancel()` propagate Task cancellation through
        // CLIProcessRunner's withTaskCancellationHandler, which terminates the child process.
        // OWNER: AICommitService — replaced atomically per run; the assignment block below clears the slot.
        // TEARDOWN: isBusy = false + inflightTask = nil run unconditionally after await task.value returns.
        // TEST: AICommitServiceCancelTests covers the cancel propagation contract.
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return AICommitResult.failure(reason: .other, message: "Service deallocated")
            }
            return await invokeAndHandle(request, args: args, successHandler: successHandler)
        }
        inflightTask = task
        let result = await task.value
        isBusy = false
        inflightTask = nil
        lastResult = result
        logger.info("AI \(request.kind.rawValue, privacy: .public) result \(String(describing: result), privacy: .public)")
        return result
    }

    private func logTaskStart(_ request: AIAgentTaskRequest) {
        logger.info(
            """
            AI \(request.kind.rawValue, privacy: .public) start \
            agent=\(request.agent.rawValue, privacy: .public) \
            cwd=\(request.projectRoot.path, privacy: .private) \
            sessionLabel=\(request.fromSessionLabel ?? "nil", privacy: .public)
            """
        )
    }

    private func invokeAndHandle(
        _ request: AIAgentTaskRequest,
        args: [String],
        successHandler: (CLIProcessOutput) async -> AICommitResult
    ) async -> AICommitResult {
        let path = await shellEnv.resolvedPath()
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path

        let output: CLIProcessOutput
        do {
            output = try await runner.run(
                executable: request.agent.defaultLaunchCommand,
                args: args,
                cwd: request.projectRoot,
                env: env,
                timeout: timeout
            )
        } catch let CLIProcessRunnerError.launchFailed(_, underlying) {
            logger.warning("AI agent launch failed: \(underlying.localizedDescription, privacy: .private)")
            return .failure(
                reason: .agentNotFound,
                message: "\(request.agent.displayName) not found in PATH — install it or check your shell config"
            )
        } catch is CancellationError {
            // CancellationError is expected — `cancel()` propagates Task cancellation to
            // CLIProcessRunner, which terminates the child; surface as a structured failure
            // so the popover toast can show "Cancelled" instead of a stack-trace style message.
            return .failure(reason: .other, message: "Cancelled")
        } catch {
            logger.warning("AI agent unexpected error: \(error.localizedDescription, privacy: .private)")
            return .failure(reason: .other, message: error.localizedDescription)
        }
        return await classify(
            output: output,
            agent: request.agent,
            kind: request.kind,
            successHandler: successHandler
        )
    }

    private func classify(
        output: CLIProcessOutput,
        agent: AgentType,
        kind: AIAgentTaskKind,
        successHandler: (CLIProcessOutput) async -> AICommitResult
    ) async -> AICommitResult {
        if output.timedOut {
            return .failure(
                reason: .timedOut,
                message: "AI task timed out — \(agent.displayName) may still be running"
            )
        }
        if AIAgentClassifier.matchesAuthFailure(stderr: output.stderr, exitCode: output.exitCode) {
            return .failure(
                reason: .authRequired,
                message: "Login required: run `\(agent.defaultLaunchCommand) login` in a terminal"
            )
        }
        if AIAgentClassifier.matchesBinaryMissing(stderr: output.stderr, exitCode: output.exitCode) {
            return .failure(
                reason: .agentNotFound,
                message: "\(agent.displayName) not found in PATH — install it or check your shell config"
            )
        }
        if kind.invokesGitCommit,
           AIAgentClassifier.matchesPreCommitHook(stderr: output.stderr, exitCode: output.exitCode) {
            return .failure(
                reason: .gitHookFailed,
                message: "Pre-commit hook failed — open a session and run `git commit` to debug"
            )
        }
        if output.exitCode != 0 {
            return .failure(reason: .other, message: AIAgentClassifier.shortErrorSnippet(output: output))
        }
        return await successHandler(output)
    }
}
