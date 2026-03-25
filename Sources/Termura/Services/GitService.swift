import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "GitService")

// MARK: - Data Models

/// Status of a single file in the git working tree.
struct GitFileStatus: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable {
        case modified, added, deleted, renamed, copied, untracked
    }

    var id: String { path }
    let path: String
    let kind: Kind
    let isStaged: Bool
}

/// Snapshot of `git status` for a project directory.
struct GitStatusResult: Sendable {
    let branch: String
    let files: [GitFileStatus]
    let isGitRepo: Bool

    static let notARepo = GitStatusResult(branch: "", files: [], isGitRepo: false)

    var stagedFiles: [GitFileStatus] { files.filter(\.isStaged) }
    var modifiedFiles: [GitFileStatus] { files.filter { !$0.isStaged && $0.kind != .untracked } }
    var untrackedFiles: [GitFileStatus] { files.filter { $0.kind == .untracked } }
}

// MARK: - Protocol

protocol GitServiceProtocol: Sendable {
    func status(at directory: String) async throws -> GitStatusResult
    func diff(file: String, staged: Bool, at directory: String) async throws -> String
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
        return Self.parse(porcelain: output)
    }

    func diff(file: String, staged: Bool, at directory: String) async throws -> String {
        var args = ["diff", "--no-color"]
        if staged { args.append("--cached") }
        args.append("--")
        args.append(file)
        return try await run(args, at: directory)
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

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let stderr = String(
                    data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let msg = "git \(arguments.joined(separator: " ")) failed (\(process.terminationStatus)): \(stderr)"
                logger.warning("\(msg)")
                continuation.resume(throwing: GitServiceError.commandFailed(msg))
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: result)
        }
    }

    // MARK: - Parser (internal for testing)

    static func parse(porcelain output: String) -> GitStatusResult {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let firstLine = lines.first, firstLine.hasPrefix("## ") else {
            return .notARepo
        }

        // Parse branch: "## main...origin/main" or "## HEAD (no branch)"
        let branchInfo = String(firstLine.dropFirst(3))
        let branch: String
        if let dotDot = branchInfo.range(of: "...") {
            branch = String(branchInfo[branchInfo.startIndex..<dotDot.lowerBound])
        } else {
            branch = branchInfo
        }

        var files: [GitFileStatus] = []
        let fileLines = lines.dropFirst().prefix(AppConfig.Git.maxDisplayedFiles)
        for line in fileLines {
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

            // Staged change (index column)
            if x != " " && x != "?" {
                let kind = Self.mapStatusChar(x)
                files.append(GitFileStatus(path: path, kind: kind, isStaged: true))
            }

            // Unstaged change (work-tree column)
            if y != " " && y != "?" {
                let kind = Self.mapStatusChar(y)
                files.append(GitFileStatus(path: path, kind: kind, isStaged: false))
            }
        }

        return GitStatusResult(branch: branch, files: files, isGitRepo: true)
    }

    private static func mapStatusChar(_ c: Character) -> GitFileStatus.Kind {
        switch c {
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
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        }
    }
}
