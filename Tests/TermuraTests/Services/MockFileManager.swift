import Foundation
@testable import Termura

// MARK: - MockFileManager

/// Test double for FileManagerProtocol.
/// Records mutations (created directories, removed paths) and allows caller-controlled
/// stubbing of existence checks, directory contents, and error injection.
// @unchecked Sendable: test-only double. All properties are mutated exclusively on the
// calling test thread before being passed to the unit under test — no concurrent access.
final class MockFileManager: FileManagerProtocol, @unchecked Sendable {
    // MARK: - Stubs

    var temporaryDirectory: URL = .init(fileURLWithPath: NSTemporaryDirectory())

    var homeDirectoryForCurrentUser: URL = .init(fileURLWithPath: NSHomeDirectory())

    /// Paths treated as existing by `fileExists(atPath:)`.
    var existingPaths: Set<String> = []

    /// Canned result returned by `contentsOfDirectory(at:includingPropertiesForKeys:options:)`.
    var stubbedContents: [URL] = []

    /// When true, `createDirectory` throws `CocoaError(.fileWriteNoPermission)`.
    var shouldThrowOnCreateDirectory = false

    /// When true, `removeItem(atPath:)` throws `CocoaError(.fileNoSuchFile)`.
    var shouldThrowOnRemoveItem = false

    // MARK: - Recorded calls

    private(set) var createdDirectoryURLs: [URL] = []
    private(set) var removedPaths: [String] = []

    // MARK: - FileManagerProtocol

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        if shouldThrowOnCreateDirectory { throw CocoaError(.fileWriteNoPermission) }
        createdDirectoryURLs.append(url)
        existingPaths.insert(url.path)
    }

    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool) throws {
        try createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: createIntermediates)
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        stubbedContents
    }

    func removeItem(atPath path: String) throws {
        if shouldThrowOnRemoveItem { throw CocoaError(.fileNoSuchFile) }
        removedPaths.append(path)
        existingPaths.remove(path)
    }

    func removeItem(at url: URL) throws {
        try removeItem(atPath: url.path)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        existingPaths.remove(srcURL.path)
        existingPaths.insert(dstURL.path)
    }
}
