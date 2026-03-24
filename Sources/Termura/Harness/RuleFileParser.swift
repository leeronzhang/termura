import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "RuleFileParser")

/// Parses Markdown-based harness rule files into structured sections.
/// Supports AGENTS.md, CLAUDE.md, .cursorrules, CONVENTIONS.md.
enum RuleFileParser {
    /// Parse a rule file's content into sections.
    static func parse(_ content: String) -> [RuleSection] {
        let lines = content.components(separatedBy: "\n")
        var sections: [RuleSection] = []
        var currentHeading: String?
        var currentLevel = 0
        var currentBody: [String] = []
        var sectionStartLine = 1

        for (index, line) in lines.enumerated() {
            let lineNum = index + 1
            if let (heading, level) = parseHeading(line) {
                // Emit previous section
                if let prevHeading = currentHeading {
                    let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    let range = sectionStartLine ... max(sectionStartLine, lineNum - 1)
                    sections.append(RuleSection(
                        heading: prevHeading, level: currentLevel,
                        body: body, lineRange: range
                    ))
                }
                currentHeading = heading
                currentLevel = level
                currentBody = []
                sectionStartLine = lineNum
            } else {
                currentBody.append(line)
            }
        }

        // Emit last section
        if let heading = currentHeading {
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let range = sectionStartLine ... max(sectionStartLine, lines.count)
            sections.append(RuleSection(
                heading: heading, level: currentLevel,
                body: body, lineRange: range
            ))
        }

        return sections
    }

    /// Detect supported rule files in a directory.
    static func findRuleFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        return AppConfig.Harness.supportedRuleFiles.compactMap { name in
            let path = (directory as NSString).appendingPathComponent(name)
            return fm.fileExists(atPath: path) ? path : nil
        }
    }

    /// Read and parse a rule file from disk.
    static func loadAndParse(at path: String) throws -> (RuleFileRecord, [RuleSection]) {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let sections = parse(content)
        let record = RuleFileRecord(filePath: path, content: content)
        return (record, sections)
    }

    // MARK: - Private

    private static func parseHeading(_ line: String) -> (String, Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for char in trimmed {
            if char == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let heading = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        guard !heading.isEmpty else { return nil }
        return (heading, level)
    }
}
