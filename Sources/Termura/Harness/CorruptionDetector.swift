import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "CorruptionDetector")

/// Scans harness rule files for potential issues: contradictions,
/// stale references, and redundancies.
actor CorruptionDetector {
    /// Run all checks against parsed sections.
    func scan(sections: [RuleSection], projectRoot: String) -> [CorruptionResult] {
        var results: [CorruptionResult] = []
        results.append(contentsOf: detectStaleFilePaths(sections, root: projectRoot))
        results.append(contentsOf: detectContradictions(sections))
        results.append(contentsOf: detectRedundancies(sections))
        return results
    }

    // MARK: - Stale File Paths

    private func detectStaleFilePaths(_ sections: [RuleSection], root: String) -> [CorruptionResult] {
        let fm = FileManager.default
        var results: [CorruptionResult] = []
        let pathPattern: NSRegularExpression?
        do {
            pathPattern = try NSRegularExpression(pattern: "`([^`]+\\.[a-zA-Z]{1,10})`")
        } catch {
            // Non-critical: static regex compilation — if this fails, stale-path check is skipped.
            // The literal pattern is well-formed, so failure here would indicate a system-level issue.
            logger.error("Failed to create corruption detector regex: \(error)")
            pathPattern = nil
        }

        for section in sections {
            guard let regex = pathPattern else { continue }
            let nsBody = section.body as NSString
            let matches = regex.matches(in: section.body, range: NSRange(location: 0, length: nsBody.length))

            for match in matches {
                guard match.numberOfRanges >= 2 else { continue }
                let pathRange = match.range(at: 1)
                let path = nsBody.substring(with: pathRange)
                let fullPath = URL(fileURLWithPath: root).appendingPathComponent(path).path

                if path.contains("/"), !fm.fileExists(atPath: fullPath) {
                    results.append(CorruptionResult(
                        severity: .warning,
                        category: .stalePath,
                        message: "Referenced file not found: \(path)",
                        sectionHeading: section.heading,
                        lineRange: section.lineRange
                    ))
                }
            }
        }
        return results
    }

    // MARK: - Contradictions

    private func detectContradictions(_ sections: [RuleSection]) -> [CorruptionResult] {
        var results: [CorruptionResult] = []
        let allBodies = sections.map { $0.body.lowercased() }

        for (i, section) in sections.enumerated() {
            let body = allBodies[i]
            // Check for "must" vs "must not" / "always" vs "never" on same topic
            if body.contains("must ") && body.contains("must not ") {
                results.append(CorruptionResult(
                    severity: .warning,
                    category: .contradiction,
                    message: "Section contains both 'must' and 'must not' — review for conflicts",
                    sectionHeading: section.heading,
                    lineRange: section.lineRange
                ))
            }
        }
        return results
    }

    // MARK: - Redundancies

    private func detectRedundancies(_ sections: [RuleSection]) -> [CorruptionResult] {
        var results: [CorruptionResult] = []
        var seen: [String: Int] = [:]

        for (i, section) in sections.enumerated() {
            let normalized = section.heading.lowercased().trimmingCharacters(in: .whitespaces)
            if let prevIdx = seen[normalized] {
                results.append(CorruptionResult(
                    severity: .info,
                    category: .redundancy,
                    message: "Duplicate heading '\(section.heading)' also at section \(prevIdx + 1)",
                    sectionHeading: section.heading,
                    lineRange: section.lineRange
                ))
            }
            seen[normalized] = i
        }
        return results
    }
}
