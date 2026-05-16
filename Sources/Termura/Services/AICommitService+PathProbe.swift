import Foundation
import OSLog

private let probeLogger = Logger(subsystem: "com.termura.app", category: "AICommitService.PathProbe")

/// PATH-probe fallback for resolving a headless-capable CLI agent when no
/// interactive session is open. Extracted so `AICommitService.swift` stays
/// inside the soft file-size budget (CLAUDE.md §6.1).
extension AICommitService {
    /// Returns the first headless-capable agent whose CLI is on the user's PATH.
    /// Result is cached for the service's lifetime — PATH does not change after
    /// the app launches, so paying the probe cost once per session is enough.
    func probeAvailableHeadlessAgent() async -> AgentType? {
        if let cached = cachedHeadlessAgent { return cached.value }
        let resolved = await resolveHeadlessAgent()
        cachedHeadlessAgent = CachedHeadlessAgent(value: resolved)
        return resolved
    }

    /// Probes `which <cmd>` for each candidate agent in priority order.
    /// claudeCode first because its headless surface produces a richer
    /// commit-subject path; codex `exec` is acceptable as a runner-up.
    private func resolveHeadlessAgent() async -> AgentType? {
        let path = await shellEnv.resolvedPath()
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        let candidates: [AgentType] = [.claudeCode, .codex]
        let probeCwd = URL(fileURLWithPath: NSHomeDirectory())
        for agent in candidates where agent.supportsHeadless {
            let cmd = agent.defaultLaunchCommand
            guard !cmd.isEmpty else { continue }
            do {
                let output = try await runner.run(
                    executable: "which",
                    args: [cmd],
                    cwd: probeCwd,
                    env: env,
                    timeout: AppConfig.AICommit.probeTimeout
                )
                let trimmed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if output.exitCode == 0, !trimmed.isEmpty {
                    return agent
                }
            } catch {
                probeLogger.debug(
                    "PATH probe failed for \(cmd, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                continue
            }
        }
        return nil
    }
}
