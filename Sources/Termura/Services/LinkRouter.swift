import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "LinkRouter")

/// Routes terminal links to internal views (note rendering, code editor) or the system handler.
///
/// P0 scope: only `.md` files inside `<project>/.termura/notes/` are routed to the internal
/// note tab. All other URLs (including HTTP, files outside notes directory) fall through to
/// `NSWorkspace.shared.open` for system-default handling.
@MainActor
final class LinkRouter: LinkRouterProtocol {
    /// Set by ProjectCoordinator when the project is opened. The router only intercepts
    /// `.md` files inside this directory.
    var notesDirectoryURL: URL?

    /// Called when a `.md` file inside `notesDirectoryURL` is clicked. The callback should
    /// open the corresponding note in an internal tab.
    var onOpenNoteByPath: ((URL) -> Void)?

    @discardableResult
    func route(url: URL, workingDirectory: String, forceExternal: Bool) -> Bool {
        if forceExternal {
            openExternal(url)
            return false
        }

        let resolved = resolveURL(url, workingDirectory: workingDirectory)
        if isMarkdownNote(resolved) {
            onOpenNoteByPath?(resolved)
            return true
        }

        openExternal(url)
        return false
    }

    // MARK: - Private

    private func isMarkdownNote(_ url: URL) -> Bool {
        guard let notesDir = notesDirectoryURL else { return false }
        let ext = url.pathExtension.lowercased()
        guard AppConfig.LinkRouting.markdownExtensions.contains(ext) else { return false }
        return url.path.hasPrefix(notesDir.standardized.path)
    }

    private func resolveURL(_ url: URL, workingDirectory: String) -> URL {
        if url.isFileURL {
            return url.standardized
        }
        if url.path.hasPrefix("/") {
            return URL(fileURLWithPath: url.path).standardized
        }
        return URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent(url.path)
            .standardized
    }

    private func openExternal(_ url: URL) {
        NSWorkspace.shared.open(url)
        logger.debug("Opened externally: \(url.absoluteString)")
    }
}
