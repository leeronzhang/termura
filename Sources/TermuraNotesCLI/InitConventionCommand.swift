import ArgumentParser
import Foundation
import TermuraNotesKit

struct InitConventionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init-convention",
        abstract: "Generate knowledge sinking convention for this project."
    )

    @Flag(name: .long, help: "Overwrite existing convention file.")
    var force = false

    func run() throws {
        let project = try ProjectDiscovery()
        try project.ensureDirectories()

        let conventionURL = project.knowledgeRoot.appendingPathComponent("CONVENTION.md")
        let fm = FileManager.default

        guard force || !fm.fileExists(atPath: conventionURL.path) else {
            throw ValidationError("CONVENTION.md already exists. Use --force to overwrite.")
        }

        try ConventionTemplate.conventionContent
            .write(to: conventionURL, atomically: true, encoding: .utf8)
        print("Created \(conventionURL.path)")

        let claudeURL = project.projectRoot.appendingPathComponent("CLAUDE.md")
        if appendClaudeReference(to: claudeURL) {
            print("Updated \(claudeURL.path) with convention reference.")
        }
    }

    /// Append the convention reference to CLAUDE.md if not already present.
    /// Returns true if the file was modified.
    @discardableResult
    private func appendClaudeReference(to url: URL) -> Bool {
        let fm = FileManager.default
        let snippet = ConventionTemplate.claudeReferenceSnippet

        if fm.fileExists(atPath: url.path) {
            do {
                let existing = try String(contentsOf: url, encoding: .utf8)
                if existing.contains(ConventionTemplate.claudeMarker) { return false }
                let updated = existing.hasSuffix("\n")
                    ? existing + "\n" + snippet + "\n"
                    : existing + "\n\n" + snippet + "\n"
                try updated.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Non-critical: CLAUDE.md update is best-effort.
                print("Warning: could not update CLAUDE.md: \(error.localizedDescription)")
                return false
            }
        } else {
            do {
                try snippet.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Non-critical: creating CLAUDE.md is best-effort.
                print("Warning: could not create CLAUDE.md: \(error.localizedDescription)")
                return false
            }
        }
        return true
    }
}
