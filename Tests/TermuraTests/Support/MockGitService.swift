import Foundation
@testable import Termura

actor MockGitService: GitServiceProtocol {
    var stubbedResult: GitStatusResult = .notARepo
    var statusCallCount = 0

    func setStubbed(_ result: GitStatusResult) { stubbedResult = result }

    func status(at directory: String) async throws -> GitStatusResult {
        statusCallCount += 1
        return stubbedResult
    }

    var stubbedDiff: String?

    func diff(file: String, staged: Bool, at directory: String) async throws -> String {
        stubbedDiff ?? ""
    }

    var stubbedTrackedFiles: Set<String> = []

    func trackedFiles(at directory: String) async throws -> Set<String> {
        stubbedTrackedFiles
    }

    var stubbedFileContent: String = ""

    func showFile(at path: String, directory: String) async throws -> String {
        stubbedFileContent
    }

    var stubbedNumstat: [DiffStat] = []

    func numstat(at directory: String) async throws -> [DiffStat] {
        stubbedNumstat
    }

    /// FIFO queue consumed by `headSHA(at:)` so a single test can stub the
    /// pre-commit and post-commit SHAs in order. When empty, falls back to
    /// `stubbedHeadSHADefault` (nil by default — same as "no HEAD yet").
    var stubbedHeadSHAQueue: [String?] = []
    var stubbedHeadSHADefault: String?
    var headSHACallCount = 0

    func enqueueHeadSHAs(_ shas: [String?]) { stubbedHeadSHAQueue.append(contentsOf: shas) }
    func setHeadSHADefault(_ sha: String?) { stubbedHeadSHADefault = sha }

    func headSHA(at directory: String) async throws -> String? {
        headSHACallCount += 1
        if !stubbedHeadSHAQueue.isEmpty {
            return stubbedHeadSHAQueue.removeFirst()
        }
        return stubbedHeadSHADefault
    }

    var stubbedLastCommitSubject: String?

    func setLastCommitSubject(_ subject: String?) { stubbedLastCommitSubject = subject }

    func lastCommitSubject(at directory: String) async throws -> String? {
        stubbedLastCommitSubject
    }
}
