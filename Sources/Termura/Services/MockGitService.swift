import Foundation

/// Test double for `GitServiceProtocol`.
actor MockGitService: GitServiceProtocol {
    var stubbedResult: GitStatusResult = .notARepo
    var statusCallCount = 0

    func status(at directory: String) async throws -> GitStatusResult {
        statusCallCount += 1
        return stubbedResult
    }

    var stubbedDiff = ""

    func diff(file: String, staged: Bool, at directory: String) async throws -> String {
        stubbedDiff
    }
}
