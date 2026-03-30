import Foundation

#if DEBUG

/// Test double for `GitServiceProtocol`.
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
}

#endif
