import Foundation
import SwiftUI

// MARK: - Protocol

/// Abstraction over FileManager to enable dependency injection and isolated unit tests.
/// Defines only the subset of FileManager methods used across Termura's business-logic layer.
/// Views and static helpers that cannot be unit-tested in isolation may continue to use
/// FileManager.default directly and are excluded from this contract.
protocol FileManagerProtocol: Sendable {
    /// The temporary directory for the current user.
    var temporaryDirectory: URL { get }
    var homeDirectoryForCurrentUser: URL { get }

    /// Returns whether a file (or directory) exists at the given path.
    func fileExists(atPath path: String) -> Bool

    /// Creates a directory at the given URL.
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws

    /// Creates a directory at the given path.
    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool) throws

    /// Returns the URLs for the items in the specified directory.
    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL]

    /// Removes the file or directory at the given path.
    func removeItem(atPath path: String) throws
    func removeItem(at url: URL) throws

    /// Atomically move a file or directory to a new location (e.g. for migrations).
    func moveItem(at srcURL: URL, to dstURL: URL) throws
}

// MARK: - FileManager conformance

extension FileManager: FileManagerProtocol {
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
    }

    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool) throws {
        try createDirectory(atPath: path, withIntermediateDirectories: createIntermediates, attributes: nil)
    }
}

private struct FileManagerKey: EnvironmentKey {
    static let defaultValue: any FileManagerProtocol = GlobalEnvironmentDefaults.fileManager
}

extension EnvironmentValues {
    var fileManager: any FileManagerProtocol {
        get { self[FileManagerKey.self] }
        set { self[FileManagerKey.self] = newValue }
    }
}
