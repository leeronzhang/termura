import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "UserShellEnvironment")

/// Resolves the PATH a child process should inherit so user-installed CLI tools
/// (e.g. `claude`, `codex` from Homebrew or npm) are discoverable.
///
/// macOS GUI apps inherit a minimal PATH that excludes user shell additions
/// (`~/.zshrc`, `/opt/homebrew/bin`, npm globals, etc.). Probing the user's
/// login shell once at startup and caching the result is the standard
/// workaround.
protocol UserShellEnvironmentProtocol: Sendable {
    /// PATH string suitable for child-process `environment["PATH"]`.
    /// Returns the cached probe result, or a fallback if probing failed.
    func resolvedPath() async -> String
}

/// Production implementation: spawns `/bin/zsh -lc 'echo $PATH'` once,
/// caches the result, falls back to the parent process PATH on failure.
actor UserShellEnvironment: UserShellEnvironmentProtocol {
    private var cached: String?
    private var probeTask: Task<String, Never>?

    func resolvedPath() async -> String {
        if let cached { return cached }
        if let probeTask { return await probeTask.value }
        let task = Task<String, Never> { await Self.probe() }
        probeTask = task
        let value = await task.value
        cached = value
        probeTask = nil
        return value
    }

    /// Forces a re-probe on next call. Mainly useful for tests.
    func invalidate() {
        cached = nil
    }

    private static func probe() async -> String {
        await withCheckedContinuation { continuation in
            // WHY: Login-shell PATH probe must run off the cooperative executor and have
            // a hard timeout in case the user's zshrc hangs (network mounts, slow init).
            // OWNER: This detached task owns the Process for the duration of the probe.
            // TEARDOWN: Process terminates on its own; if it hangs past pathProbeTimeout
            // we resume the continuation with the fallback PATH and let the OS reap it.
            // TEST: Cover the success path, the timeout path, and a malformed-output path.
            Task.detached(priority: .utility) {
                let result = runProbe()
                continuation.resume(returning: result)
            }
        }
    }

    private static func runProbe() -> String {
        // WHY: One-shot login-shell PATH probe must run synchronously here (called from a
        // detached probe task) so the cached value is ready before any caller awaits it.
        // OWNER: This function owns the Process for one invocation; teardown via terminate() on timeout.
        // TEARDOWN: If the deadline elapses while the process still runs, we SIGTERM it
        // and let the OS reap; the function returns the fallback PATH.
        // TEST: Cover success / timeout / non-zero exit / empty output via integration spec.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = AppConfig.AICommit.pathProbeCommand
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            logger.warning("PATH probe failed to launch: \(error.localizedDescription)")
            return fallbackPath()
        }

        let timeoutSeconds = AppConfig.AICommit.pathProbeTimeout.totalSeconds
        let start = ContinuousClock.now
        while process.isRunning {
            let elapsed = (ContinuousClock.now - start).totalSeconds
            if elapsed >= timeoutSeconds { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            logger.warning("PATH probe timed out — falling back to parent env PATH")
            return fallbackPath()
        }

        guard process.terminationStatus == 0 else {
            logger.warning("PATH probe exited non-zero (\(process.terminationStatus)) — using fallback")
            return fallbackPath()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if output.isEmpty {
            logger.warning("PATH probe returned empty output — using fallback")
            return fallbackPath()
        }
        return output
    }

    private static func fallbackPath() -> String {
        ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    }
}

/// Mock used by tests to inject a deterministic PATH without spawning a shell.
struct StaticUserShellEnvironment: UserShellEnvironmentProtocol {
    let path: String
    func resolvedPath() async -> String { path }
}
