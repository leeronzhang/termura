import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "GitService")

// MARK: - Protocol

protocol GitServiceProtocol: Sendable {
    func status(at directory: String) async throws -> GitStatusResult
    func diff(file: String, staged: Bool, at directory: String) async throws -> String
    /// Returns the set of file paths tracked by git (relative to the repo root).
    func trackedFiles(at directory: String) async throws -> Set<String>
}

// MARK: - Live Implementation

/// Actor that shells out to the `git` CLI to query repository state.
actor GitService: GitServiceProtocol {

    func status(at directory: String) async throws -> GitStatusResult {
        guard await isGitRepo(at: directory) else {
            return .notARepo
        }

        let output = try await run(
            ["status", "--porcelain=v1", "-b", "--no-renames"],
            at: directory
        )
        var result = Self.parse(porcelain: output)

        // Fetch last commit message (non-fatal if fails, e.g. empty repo)
        do {
            let logLine = try await run(
                ["log", "-1", "--oneline", "--no-decorate"],
                at: directory
            )
            result.lastCommit = logLine.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Non-critical: last commit is a display-only field; empty repos have no log.
            logger.debug("Could not read last commit: \(error.localizedDescription)")
        }

        // Fetch remote host label
        do {
            let url = try await run(
                ["remote", "get-url", "origin"],
                at: directory
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            result.remoteHost = Self.parseRemoteHost(from: url)
        } catch {
            // Non-critical: remote URL is a display-only field; local-only repos have no remote.
            logger.debug("No remote origin: \(error.localizedDescription)")
        }

        return result
    }

    func diff(file: String, staged: Bool, at directory: String) async throws -> String {
        var args = ["diff", "--no-color"]
        if staged { args.append("--cached") }
        args.append("--")
        args.append(file)
        return try await run(args, at: directory)
    }

    func trackedFiles(at directory: String) async throws -> Set<String> {
        let output = try await run(["ls-files"], at: directory)
        let paths = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return Set(paths)
    }

    /// Returns the full file content for untracked files (no diff available).
    func showFile(at path: String, directory: String) async throws -> String {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Helpers

    private func isGitRepo(at directory: String) async -> Bool {
        do {
            let out = try await run(["rev-parse", "--is-inside-work-tree"], at: directory)
            return out.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            // Non-critical: non-git directories return false — caller handles the fallback.
            logger.debug("Not a git repo at \(directory): \(error.localizedDescription)")
            return false
        }
    }

    private func run(_ arguments: [String], at directory: String) async throws -> String {
        let cmdString = arguments.joined(separator: " ")
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.executeProcess(arguments, at: directory, cmdString: cmdString)
            }
            group.addTask {
                // Hard timeout — if git hangs (lock file, network mount), kill after deadline.
                try await Task.sleep(nanoseconds: AppConfig.Git.commandTimeoutNanoseconds)
                throw GitServiceError.commandFailed(
                    command: cmdString,
                    exitCode: -1,
                    stderr: "Timed out after \(AppConfig.Git.commandTimeoutNanoseconds / 1_000_000_000)s"
                )
            }
            // The first task to complete wins; the other is cancelled.
            guard let result = try await group.next() else {
                throw GitServiceError.commandFailed(command: cmdString, exitCode: -1, stderr: "No result")
            }
            group.cancelAll()
            return result
        }
    }

    private func executeProcess(
        _ arguments: [String],
        at directory: String,
        cmdString: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            process.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            // Resume the continuation asynchronously when the process exits.
            process.terminationHandler = { terminatedProcess in
                guard terminatedProcess.terminationStatus == 0 else {
                    let stderr = String(
                        data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    let error = GitServiceError.commandFailed(
                        command: cmdString,
                        exitCode: terminatedProcess.terminationStatus,
                        stderr: stderr
                    )
                    logger.warning("\(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: GitServiceError.launchFailed(
                    command: cmdString,
                    underlying: error
                ))
            }
        }
    }

}
