import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "CorruptionDetector")

/// Scans harness rule files for potential issues: stale paths, contradictions, redundancies.
actor CorruptionDetector {
    func scan(sections: [RuleSection], projectRoot: String) -> [CorruptionResult] {
        var results: [CorruptionResult] = []
        results.append(contentsOf: detectStaleFilePaths(sections, root: projectRoot))
        results.append(contentsOf: detectContradictions(sections))
        results.append(contentsOf: detectRedundancies(sections))
        return results
    }

    private func detectStaleFilePaths(_ sections: [RuleSection], root: String) -> [CorruptionResult] {
        let fm = FileManager.default
        var results: [CorruptionResult] = []
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: "`([^`]+\\.[a-zA-Z]{1,10})`")
        } catch {
            logger.error("Failed to create stale-path regex: \(error.localizedDescription)")
            return results
        }
        for section in sections {
            let nsBody = section.body as NSString
            let matches = regex.matches(in: section.body, range: NSRange(location: 0, length: nsBody.length))
            for match in matches {
                guard match.numberOfRanges >= 2 else { continue }
                let path = nsBody.substring(with: match.range(at: 1))
                let fullPath = URL(fileURLWithPath: root).appendingPathComponent(path).path
                if path.contains("/"), !fm.fileExists(atPath: fullPath) {
                    results.append(CorruptionResult(
                        severity: .warning, category: .stalePath,
                        message: "Referenced file not found: \(path)",
                        sectionHeading: section.heading, lineRange: section.lineRange
                    ))
                }
            }
        }
        return results
    }

    private func detectContradictions(_ sections: [RuleSection]) -> [CorruptionResult] {
        sections.compactMap { section in
            let body = section.body.lowercased()
            guard body.contains("must ") && body.contains("must not ") else { return nil }
            return CorruptionResult(
                severity: .warning, category: .contradiction,
                message: "Section contains both 'must' and 'must not' — review for conflicts",
                sectionHeading: section.heading, lineRange: section.lineRange
            )
        }
    }

    private func detectRedundancies(_ sections: [RuleSection]) -> [CorruptionResult] {
        var seen: [String: Int] = [:]
        var results: [CorruptionResult] = []
        for (i, section) in sections.enumerated() {
            let normalized = section.heading.lowercased().trimmingCharacters(in: .whitespaces)
            if let prevIdx = seen[normalized] {
                results.append(CorruptionResult(
                    severity: .info, category: .redundancy,
                    message: "Duplicate heading '\(section.heading)' also at section \(prevIdx + 1)",
                    sectionHeading: section.heading, lineRange: section.lineRange
                ))
            }
            seen[normalized] = i
        }
        return results
    }
}
