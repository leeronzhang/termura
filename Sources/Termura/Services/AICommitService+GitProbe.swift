import Foundation
import OSLog

private let gitProbeLogger = Logger(subsystem: "com.termura.app", category: "AICommitService.GitProbe")

/// Static git-state probes the commit pipeline uses to verify a commit really
/// happened. Extracted from `AICommitService.swift` so the main file stays
/// inside the soft file-size budget (CLAUDE.md §6.1).
extension AICommitService {
    /// Best-effort HEAD snapshot. Returns nil when the repo has no commits yet
    /// or when the git CLI itself fails; the caller treats nil-equality as
    /// "no commit happened" (which is the conservative interpretation).
    static func snapshotHEAD(
        projectRoot: URL,
        gitService: any GitServiceProtocol
    ) async -> String? {
        do {
            return try await gitService.headSHA(at: projectRoot.path)
        } catch {
            gitProbeLogger.debug("HEAD snapshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func fetchCommitSubject(
        projectRoot: URL,
        gitService: any GitServiceProtocol
    ) async -> String? {
        do {
            return try await gitService.lastCommitSubject(at: projectRoot.path)
        } catch {
            gitProbeLogger.debug("Commit subject fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
