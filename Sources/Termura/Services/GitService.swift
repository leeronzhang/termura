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
            logger.debug("Not a git repo at \(directory): \(error.localizedDescription)")
            return false
        }
    }

    private func run(_ arguments: [String], at directory: String) async throws -> String {
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
            // This avoids blocking the Swift concurrency cooperative thread pool.
            let cmdString = arguments.joined(separator: " ")
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
                // Clear terminationHandler to prevent double-resume if launch fails.
                process.terminationHandler = nil
                continuation.resume(throwing: GitServiceError.launchFailed(
                    command: cmdString,
                    underlying: error
                ))
            }
        }
    }

    // MARK: - Parser (internal for testing)

    static func parse(porcelain output: String) -> GitStatusResult {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let firstLine = lines.first, firstLine.hasPrefix("## ") else {
            return .notARepo
        }

        let branchInfo = String(firstLine.dropFirst(3))
        let header = parseBranchHeader(branchInfo)
        let files = parseFileStatuses(lines.dropFirst())

        return GitStatusResult(
            branch: header.branch, files: files, isGitRepo: true,
            ahead: header.ahead, behind: header.behind
        )
    }

    // MARK: - Parse Helpers

    private struct BranchHeader {
        let branch: String
        let ahead: Int
        let behind: Int
    }

    private static func parseBranchHeader(_ branchInfo: String) -> BranchHeader {
        var ahead = 0
        var behind = 0

        let bracketParts = branchInfo.components(separatedBy: " [")
        let branchPart = bracketParts[0]

        let branch: String
        if let dotDot = branchPart.range(of: "...") {
            branch = String(branchPart[branchPart.startIndex..<dotDot.lowerBound])
        } else {
            branch = branchPart
        }

        if bracketParts.count > 1 {
            let info = bracketParts[1].replacingOccurrences(of: "]", with: "")
            for part in info.components(separatedBy: ", ") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("ahead "),
                   let val = Int(trimmed.dropFirst(6)) {
                    ahead = val
                } else if trimmed.hasPrefix("behind "),
                          let val = Int(trimmed.dropFirst(7)) {
                    behind = val
                }
            }
        }

        return BranchHeader(branch: branch, ahead: ahead, behind: behind)
    }

    private static func parseFileStatuses(
        _ lines: some Collection<String>
    ) -> [GitFileStatus] {
        var files: [GitFileStatus] = []
        let capped = lines.prefix(AppConfig.Git.maxDisplayedFiles)

        for line in capped {
            guard line.count >= 4 else { continue }
            let index = line.index(line.startIndex, offsetBy: 0)
            let workTree = line.index(line.startIndex, offsetBy: 1)
            let pathStart = line.index(line.startIndex, offsetBy: 3)
            let x = line[index]
            let y = line[workTree]
            let path = String(line[pathStart...])

            if x == "?" && y == "?" {
                files.append(GitFileStatus(path: path, kind: .untracked, isStaged: false))
                continue
            }

            if x != " " && x != "?" {
                let kind = mapStatusChar(x)
                files.append(GitFileStatus(path: path, kind: kind, isStaged: true))
            }

            if y != " " && y != "?" {
                let kind = mapStatusChar(y)
                files.append(GitFileStatus(path: path, kind: kind, isStaged: false))
            }
        }

        return files
    }

    /// Extract a short host label from a remote URL.
    /// "git@github.com:user/repo" → "GitHub"
    /// "https://gitlab.com/user/repo" → "GitLab"
    static func parseRemoteHost(from url: String) -> String {
        let lowered = url.lowercased()
        if lowered.contains("github.com") { return "GitHub" }
        if lowered.contains("gitlab.com") { return "GitLab" }
        if lowered.contains("bitbucket.org") { return "Bitbucket" }
        if lowered.contains("gitee.com") { return "Gitee" }
        if lowered.contains("codeberg.org") { return "Codeberg" }
        if lowered.contains("sr.ht") { return "SourceHut" }
        if lowered.contains("dev.azure.com") || lowered.contains("visualstudio.com") {
            return "Azure DevOps"
        }
        // Fallback: extract hostname
        if let hostRange = url.range(of: "@") {
            let afterAt = url[hostRange.upperBound...]
            if let colon = afterAt.firstIndex(of: ":") {
                return String(afterAt[afterAt.startIndex..<colon])
            }
        }
        if let host = URL(string: url)?.host {
            return host
        }
        return ""
    }

    private static func mapStatusChar(_ char: Character) -> GitFileStatus.Kind {
        switch char {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        default: return .modified
        }
    }
}

// MARK: - Errors

enum GitServiceError: Error, LocalizedError {
    /// The git process exited with a non-zero status.
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    /// The git executable could not be launched (e.g., not installed, permission denied).
    case launchFailed(command: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, exitCode, stderr):
            "git \(command) failed (\(exitCode)): \(stderr)"
        case let .launchFailed(command, underlying):
            "Failed to launch git \(command): \(underlying.localizedDescription)"
        }
    }

    /// Whether the caller may retry this operation (e.g., transient I/O issue).
    var isRetryable: Bool {
        switch self {
        case .commandFailed(_, let code, _):
            // Exit codes 128+ are often transient (lock file, network).
            code >= 128
        case .launchFailed:
            false
        }
    }
}
