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
    private(set) var lastResult: AICommitResult?

    @ObservationIgnored private let runner: any CLIProcessRunnerProtocol
    @ObservationIgnored private let shellEnv: any UserShellEnvironmentProtocol
    @ObservationIgnored private let gitService: any GitServiceProtocol
    @ObservationIgnored private let timeout: Duration

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
            taskName: "commit",
            prompt: AICommitPrompts.commit(note: note),
            projectRoot: projectRoot,
            agent: agent,
            fromSessionLabel: fromSessionLabel,
            preCommitHookCheck: true
        )
        return await runAgentTask(request) { [gitService] output in
            let didCommit = await Self.committedSomething(
                projectRoot: projectRoot, gitService: gitService
            )
            if !didCommit {
                return .failure(
                    reason: .agentDeclined,
                    message: "\(agent.displayName) did not commit. See terminal for details."
                )
            }
            return .success(summary: AIAgentClassifier.commitSubject(from: output) ?? "Committed")
        }
    }

    func setupRemote(
        note: String?,
        projectRoot: URL,
        agent: AgentType,
        fromSessionLabel: String?
    ) async -> AICommitResult {
        let request = AIAgentTaskRequest(
            taskName: "remote-setup",
            prompt: AICommitPrompts.remoteSetup(note: note),
            projectRoot: projectRoot,
            agent: agent,
            fromSessionLabel: fromSessionLabel,
            preCommitHookCheck: false
        )
        return await runAgentTask(request) { _ in
            // Exit 0 + no auth/binary failure is enough. The agent has its own tool access;
            // if it succeeded, trust the exit code.
            .success(summary: "Remote configured")
        }
    }

    // MARK: - Shared task runner

    /// Runs the request's prompt headless on its agent, classifies common failures,
    /// and on a clean exit hands the raw output to `successHandler`.
    private func runAgentTask(
        _ request: AIAgentTaskRequest,
        successHandler: (CLIProcessOutput) async -> AICommitResult
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
        defer { isBusy = false }
        logTaskStart(request)

        let result = await invokeAndHandle(request, args: args, successHandler: successHandler)
        lastResult = result
        logger.info("AI \(request.taskName, privacy: .public) result \(String(describing: result), privacy: .public)")
        return result
    }

    private func logTaskStart(_ request: AIAgentTaskRequest) {
        logger.info(
            """
            AI \(request.taskName, privacy: .public) start \
            agent=\(request.agent.rawValue, privacy: .public) \
            cwd=\(request.projectRoot.path, privacy: .public) \
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
            logger.warning("AI agent launch failed: \(underlying.localizedDescription, privacy: .public)")
            return .failure(
                reason: .agentNotFound,
                message: "\(request.agent.displayName) not found in PATH — install it or check your shell config"
            )
        } catch {
            logger.warning("AI agent unexpected error: \(error.localizedDescription, privacy: .public)")
            return .failure(reason: .other, message: error.localizedDescription)
        }
        return await classify(
            output: output,
            agent: request.agent,
            preCommitHookCheck: request.preCommitHookCheck,
            successHandler: successHandler
        )
    }

    private func classify(
        output: CLIProcessOutput,
        agent: AgentType,
        preCommitHookCheck: Bool,
        successHandler: (CLIProcessOutput) async -> AICommitResult
    ) async -> AICommitResult {
        if output.timedOut {
            return .failure(
                reason: .timedOut,
                message: "AI task timed out — \(agent.displayName) may still be running"
            )
        }
        if AIAgentClassifier.matchesAuthFailure(stderr: output.stderr, stdout: output.stdout) {
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
        if preCommitHookCheck,
           AIAgentClassifier.matchesPreCommitHook(stderr: output.stderr, stdout: output.stdout) {
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

    private static func committedSomething(
        projectRoot: URL,
        gitService: any GitServiceProtocol
    ) async -> Bool {
        // After a successful AI commit, the working tree should be clean.
        // Status query failure → be permissive and trust the agent's exit code.
        do {
            let after = try await gitService.status(at: projectRoot.path)
            return after.files.isEmpty
        } catch {
            return true
        }
    }
}
