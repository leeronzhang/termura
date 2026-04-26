import Foundation

/// One project-file mention found inside a note body.
public struct ProjectFileReference: Sendable, Equatable {
    /// Path relative to the project root (e.g. `Sources/Foo.swift`).
    public let projectFilePath: String
    /// How many times this path appeared in the note body.
    public let mentionCount: Int

    public init(projectFilePath: String, mentionCount: Int) {
        self.projectFilePath = projectFilePath
        self.mentionCount = mentionCount
    }
}

/// Scans a note body for substrings that look like paths to existing project files.
///
/// Heuristic with two passes:
///   1. Inline-code spans (`` `Sources/Foo.swift` ``) — high-precision signal.
///   2. Plain-text path-shaped substrings — only counted when the resolved file
///      actually exists under `projectRoot`. This rejects hallucinated paths,
///      URLs, and stack traces from unrelated projects.
///
/// Output is deduped by path; `mentionCount` aggregates both inline and plain-text matches.
public enum ProjectFileReferenceExtractor {
    /// Path-like tokens use these suffixes. Liberal on purpose — verifying file existence
    /// downstream filters out anything not in the actual project tree.
    public static let recognizedExtensions: Set<String> = [
        "swift", "m", "h", "c", "cpp", "rs", "go", "py", "rb", "js", "ts",
        "jsx", "tsx", "json", "yaml", "yml", "toml", "xml", "plist",
        "html", "css", "scss", "less", "sh", "bash", "zsh", "fish",
        "md", "markdown", "txt", "log", "sql", "graphql",
        "vue", "svelte", "java", "kt", "scala", "dart", "php"
    ]

    /// Inline code regex: `` `path/with/optional/segments.ext` ``.
    private static let inlineCodePattern = #"`([^`\n]+\.[A-Za-z0-9]+)`"#
    /// Plain-text path regex: bare token containing `/` and a known extension.
    /// Anchored on whitespace / punctuation boundaries to avoid mid-URL matches.
    private static let plainPathPattern =
        #"(?:^|[\s(\[{,;:])([A-Za-z0-9_.\-/]+/[A-Za-z0-9_.\-]+\.[A-Za-z0-9]+)(?=[\s)\]}.,;:!?]|$)"#

    /// Returns the set of project-file mentions found in `body`. Each entry's path
    /// is verified to exist under `projectRoot`; non-existent matches are dropped.
    public static func extract(
        from body: String,
        projectRoot: URL,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> [ProjectFileReference] {
        guard !body.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for match in matches(in: body, pattern: inlineCodePattern) + matches(in: body, pattern: plainPathPattern) {
            let candidate = match.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPathShaped(candidate) else { continue }
            let absolute = projectRoot.appendingPathComponent(candidate)
                .standardizedFileURL.path
            guard fileExists(absolute) else { continue }
            counts[candidate, default: 0] += 1
        }
        return counts
            .map { ProjectFileReference(projectFilePath: $0.key, mentionCount: $0.value) }
            .sorted { $0.projectFilePath < $1.projectFilePath }
    }

    // MARK: - Helpers

    private static func isPathShaped(_ candidate: String) -> Bool {
        guard candidate.contains("/") else { return false }
        guard !candidate.hasPrefix("http://"),
              !candidate.hasPrefix("https://"),
              !candidate.hasPrefix("/")
        else { return false }
        let ext = (candidate as NSString).pathExtension.lowercased()
        return recognizedExtensions.contains(ext)
    }

    private static func matches(in body: String, pattern: String) -> [String] {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            // Non-critical: hard-coded pattern is invalid; skip silently and return no matches.
            return []
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        return regex.matches(in: body, range: range).compactMap { result in
            guard result.numberOfRanges >= 2 else { return nil }
            return nsBody.substring(with: result.range(at: 1))
        }
    }
}

/// Small helper that pulls wiki-link targets out of a note body.
/// Shared between BacklinkIndex (in-memory) and the GRDB sync pipeline so the
/// regex lives in one place.
public enum WikiLinkExtractor {
    /// `[[target]]` or `[[target|display]]` — captures `target`.
    public static let pattern = #"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]"#

    /// Returns deduplicated target titles (case preserved as written).
    public static func extract(from body: String) -> [String] {
        guard !body.isEmpty else { return [] }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            // Non-critical: hard-coded pattern is invalid; skip silently and return no matches.
            return []
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        var seen = Set<String>()
        var ordered: [String] = []
        for match in regex.matches(in: body, range: range) {
            guard match.numberOfRanges >= 2 else { continue }
            let target = nsBody.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty, seen.insert(target.lowercased()).inserted else { continue }
            ordered.append(target)
        }
        return ordered
    }
}
