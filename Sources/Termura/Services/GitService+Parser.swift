import Foundation

// MARK: - Parser (internal for testing)

extension GitService {
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
            code >= 128
        case .launchFailed:
            false
        }
    }
}
