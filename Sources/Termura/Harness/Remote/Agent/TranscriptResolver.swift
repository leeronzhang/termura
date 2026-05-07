// Wave 8 — maps a Termura session's working directory to the most
// recently active Claude Code transcript file, so `LiveAgentEventSource`
// knows which JSONL to watch.
//
// Claude Code writes one transcript per session at:
//   ~/.claude/projects/<encoded-cwd>/<claudeSessionId>.jsonl
// where `<encoded-cwd>` is the absolute cwd with `/` replaced by `-`
// (e.g. `/Users/leeron/Documents/Codes/termura` →
// `-Users-leeron-Documents-Codes-termura`).
//
// One Termura session ↔ one Claude Code transcript: a Termura PTY
// running `claude` in a given cwd produces a transcript in the
// matching project directory. Multiple `claude` invocations in the
// same cwd write multiple JSONLs; we pick the most recently
// **modified** one so we follow the live conversation.
//
// MVP simplification: no PID / parent-process matching — the
// "most recently mtime'd" heuristic correctly tracks the active
// session in the common case (one `claude` instance per cwd).

import Foundation

enum TranscriptResolver {
    /// Returns the absolute path of the most recently modified
    /// `.jsonl` transcript under `~/.claude/projects/<encoded-cwd>/`,
    /// or `nil` when:
    ///   - the project directory does not exist (Claude Code never
    ///     ran in this cwd)
    ///   - no `.jsonl` file is present yet
    ///   - the FileManager call fails (permission, etc.)
    static func latestTranscriptPath(forCwd cwd: String) -> String? {
        let encoded = encodeCwd(cwd)
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let projectDir = homeDirectory
            .appendingPathComponent(".claude/projects/\(encoded)", isDirectory: true)
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsSubdirectoryDescendants]
            )
        } catch {
            return nil
        }
        let candidates = entries.filter { $0.pathExtension == "jsonl" }
        let mostRecent = candidates.max { lhs, rhs in
            modificationDate(of: lhs) < modificationDate(of: rhs)
        }
        return mostRecent?.path
    }

    /// Encode the cwd the way Claude Code does for its project
    /// directory name. `/` → `-`; the leading slash becomes a leading
    /// `-` so `/Users/leeron` becomes `-Users-leeron`.
    static func encodeCwd(_ cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }

    private static func modificationDate(of url: URL) -> Date {
        do {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return values.contentModificationDate ?? .distantPast
        } catch {
            // Sorting fallback: a file we can't stat sorts as the
            // oldest, so it loses to any successfully-stat'd entry.
            return .distantPast
        }
    }
}
