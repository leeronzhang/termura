import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "MarkdownFileView.FileIO")

/// File-system reads / writes for `MarkdownFileView`. Pulled into their
/// own file so the main view stays under §6.1's 250-line soft cap.
/// Both helpers enforce project-root containment (resolving symlinks)
/// before touching disk.
extension MarkdownFileView {
    func loadFile() async {
        let path = absolutePath
        let root = projectRoot
        // WHY: File reads must leave MainActor while enforcing project-root containment.
        // OWNER: loadFile owns this detached read and awaits the Result immediately.
        // TEARDOWN: The detached task ends after one read and does not escape this method.
        // TEST: Cover successful reads, containment rejection, and file-read failure.
        let result: Result<String, Error> = await Task.detached {
            if !path.hasPrefix("/") {
                let resolvedFile = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
                guard resolvedFile.hasPrefix(resolvedRoot + "/") || resolvedFile == resolvedRoot else {
                    return .failure(CocoaError(.fileReadNoPermission))
                }
            }
            return Result { try String(contentsOfFile: path, encoding: .utf8) }
        }.value
        switch result {
        case let .success(text):
            content = text
        case let .failure(error):
            logger.warning("Failed to read \(path): \(error.localizedDescription)")
            errorMessage = "Cannot read file"
        }
        isLoading = false
    }

    func saveFile() {
        let path = absolutePath
        let root = projectRoot
        let text = content
        Task {
            do {
                // WHY: Saving must keep blocking file I/O off MainActor.
                // OWNER: The enclosing Task owns this detached write and awaits it.
                // TEARDOWN: The detached task ends after one write attempt.
                // TEST: Cover successful save, containment rejection, and failure.
                try await Task.detached {
                    if !path.hasPrefix("/") {
                        let resolvedFile = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                        let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
                        guard resolvedFile.hasPrefix(resolvedRoot + "/") || resolvedFile == resolvedRoot else {
                            throw CocoaError(.fileWriteNoPermission)
                        }
                    }
                    try text.write(toFile: path, atomically: true, encoding: .utf8)
                }.value
                isModified = false
                logger.info("Saved \(path)")
            } catch {
                logger.warning("Failed to save \(path): \(error.localizedDescription)")
            }
        }
    }
}
