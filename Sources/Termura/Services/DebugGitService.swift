import Foundation

#if DEBUG

/// Debug fallback for previews and local environment defaults.
actor DebugGitService: GitServiceProtocol {
    var stubbedResult: GitStatusResult = .notARepo

    func status(at directory: String) async throws -> GitStatusResult {
        stubbedResult
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
}

#endif
