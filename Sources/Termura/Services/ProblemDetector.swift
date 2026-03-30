import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProblemDetector")

/// Parses compiler and linter output lines from a completed OutputChunk into DiagnosticItems.
///
/// All methods are pure static functions — no state, no side effects.
/// Patterns cover Swift/SwiftLint (same output format), TypeScript, and a generic fallback.
/// Additional language patterns can be added as static properties without changing the API.
enum ProblemDetector {

    // MARK: - Pre-compiled patterns

    // Swift compiler / Xcode / SwiftLint: /path/File.swift:10:5: error: message
    private static let swiftPattern: NSRegularExpression? = buildPattern(
        #"^(.+\.swift):(\d+):(\d+): (error|warning|note): (.+)$"#
    )

    // TypeScript compiler: /path/file.ts(10,5): error TS2345: message
    private static let tsPattern: NSRegularExpression? = buildPattern(
        #"^(.+\.(?:ts|tsx|js|jsx))\((\d+),(\d+)\): (error|warning) TS\d+: (.+)$"#
    )

    // Generic fallback — Go compiler, Cargo, and other file:line: severity: msg formats
    private static let genericPattern: NSRegularExpression? = buildPattern(
        #"^(.+):(\d+): (error|warning): (.+)$"#
    )

    // MARK: - Internal match type

    private struct MatchData {
        let file: String
        let line: Int?
        let column: Int?
        let severity: DiagnosticSeverity
        let message: String
    }

    // MARK: - Public API

    /// Extracts DiagnosticItems from a completed OutputChunk.
    ///
    /// Returns an empty array when the chunk exits cleanly and has no error-typed content,
    /// so a successful `swift build` automatically clears previously collected diagnostics.
    static func detect(from chunk: OutputChunk, projectRoot: String) -> [DiagnosticItem] {
        guard chunk.exitCode != 0 || chunk.contentType == .error else { return [] }
        let src = source(from: chunk.commandText)
        var items: [DiagnosticItem] = []
        for line in chunk.outputLines {
            guard line.count >= 10,
                  !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let item = matchSwift(line, source: src, chunk: chunk, root: projectRoot) {
                items.append(item)
            } else if let item = matchTS(line, source: src, chunk: chunk, root: projectRoot) {
                items.append(item)
            } else if let item = matchGeneric(line, source: src, chunk: chunk, root: projectRoot) {
                items.append(item)
            }
            if items.count >= AppConfig.Diagnostics.maxItemsPerChunk { break }
        }
        return items
    }

    /// Infers the originating tool from the command text.
    /// Used to group and clear stale diagnostics when the same command reruns.
    static func source(from commandText: String) -> String {
        let cmd = commandText.lowercased()
        if cmd.contains("swiftlint") { return "swiftlint" }
        if cmd.contains("xcodebuild") { return "xcodebuild" }
        if cmd.contains("swift build") || cmd.contains("swift test") { return "swift" }
        if cmd.contains("tsc") { return "tsc" }
        if cmd.contains("cargo") { return "cargo" }
        if cmd.contains("go build") || cmd.contains("go test") { return "go" }
        return "shell"
    }

    // MARK: - Private matchers

    private static func matchSwift(
        _ line: String, source: String, chunk: OutputChunk, root: String
    ) -> DiagnosticItem? {
        guard let g = captures(swiftPattern, in: line), g.count >= 5 else { return nil }
        let data = MatchData(
            file: g[0], line: Int(g[1]), column: Int(g[2]),
            severity: parseSeverity(g[3], fallback: .note),
            message: g[4]
        )
        return makeItem(data, source: source, chunk: chunk, root: root)
    }

    private static func matchTS(
        _ line: String, source: String, chunk: OutputChunk, root: String
    ) -> DiagnosticItem? {
        guard let g = captures(tsPattern, in: line), g.count >= 5 else { return nil }
        let data = MatchData(
            file: g[0], line: Int(g[1]), column: Int(g[2]),
            severity: parseSeverity(g[3], fallback: .warning),
            message: g[4]
        )
        return makeItem(data, source: source, chunk: chunk, root: root)
    }

    private static func matchGeneric(
        _ line: String, source: String, chunk: OutputChunk, root: String
    ) -> DiagnosticItem? {
        guard let g = captures(genericPattern, in: line), g.count >= 4 else { return nil }
        let data = MatchData(
            file: g[0], line: Int(g[1]), column: nil,
            severity: parseSeverity(g[2], fallback: .note),
            message: g[3]
        )
        return makeItem(data, source: source, chunk: chunk, root: root)
    }

    /// Parses a severity string captured from a regex group.
    /// Each pattern constrains its severity group to known DiagnosticSeverity raw values,
    /// so init(rawValue:) should always succeed. assertionFailure + logger.error catch any
    /// pattern/enum drift in Debug builds; Release degrades to the context-appropriate fallback.
    private static func parseSeverity(_ raw: String, fallback: DiagnosticSeverity) -> DiagnosticSeverity {
        guard let sev = DiagnosticSeverity(rawValue: raw) else {
            assertionFailure("Unexpected severity '\(raw)'; sync regex pattern with DiagnosticSeverity cases")
            logger.error("ProblemDetector: unexpected severity '\(raw)'; sync regex pattern with DiagnosticSeverity")
            return fallback
        }
        return sev
    }

    private static func makeItem(
        _ data: MatchData, source: String, chunk: OutputChunk, root: String
    ) -> DiagnosticItem {
        DiagnosticItem(
            id: UUID(),
            file: normalize(path: data.file, projectRoot: root),
            line: data.line,
            column: data.column,
            severity: data.severity,
            message: data.message.trimmingCharacters(in: .whitespaces),
            source: source,
            sessionID: chunk.sessionID,
            producedAt: chunk.finishedAt ?? chunk.startedAt
        )
    }

    // MARK: - Helpers

    /// Returns capture group strings for the first match of `pattern` in `line`, or nil.
    /// Returns nil when pattern is nil (failed to compile — logged at startup).
    private static func captures(
        _ pattern: NSRegularExpression?, in line: String
    ) -> [String]? {
        guard let pattern else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = pattern.firstMatch(in: line, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { nsLine.substring(with: match.range(at: $0)) }
    }

    /// Strips the project root prefix from absolute paths so the UI shows relative paths.
    private static func normalize(path: String, projectRoot: String) -> String {
        let root = projectRoot.hasSuffix("/") ? projectRoot : projectRoot + "/"
        guard path.hasPrefix(root) else { return path }
        return String(path.dropFirst(root.count))
    }

    /// Compiles a regex pattern from a known-valid string literal.
    /// Returns nil and logs an error on failure — this would only occur during development
    /// if a pattern string is accidentally malformed.
    private static func buildPattern(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            logger.error("ProblemDetector: invalid regex '\(pattern)': \(error)")
            return nil
        }
    }
}
