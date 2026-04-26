import AppKit
import CoreText
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AppDelegate+Startup")

// MARK: - Startup-only helpers

//
// One-shot work that runs at `applicationDidFinishLaunching`:
// - bundled-font registration (must happen before any UI / FontSettings init)
// - stale temp-image janitor (image-paste files left over from previous sessions)
//
// Split out of `AppDelegate.swift` to keep the delegate body focused on
// lifecycle hooks and delegate methods (CLAUDE.md §6.1).

extension AppDelegate {
    /// Deletes PNG files in `~/.termura/tmp/` older than `AppConfig.DragDrop.staleImageAgeSeconds`.
    /// These are created by drag/paste operations in the terminal and editor; once dropped,
    /// the path is consumed as shell text and the file is no longer tracked. Files must
    /// survive the current session (the user may still be composing the command), but can
    /// safely be removed on the next launch. Runs off the main thread to avoid blocking startup.
    static func cleanStaleTempImages() {
        // WHY: Startup cleanup must not block app launch on filesystem work.
        // OWNER: AppDelegate launches this detached task during app startup.
        // TEARDOWN: Fire-and-forget startup work; no retained handle is needed after one-shot cleanup completes.
        // TEST: Cover stale-file deletion and preservation of fresh temp images.
        Task.detached {
            let fm = FileManager.default
            let tmpDir = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(AppConfig.DragDrop.tempImageSubdirectory)
            guard fm.fileExists(atPath: tmpDir.path) else { return }
            let cutoff = Date().timeIntervalSinceReferenceDate - AppConfig.DragDrop.staleImageAgeSeconds
            do {
                let contents = try fm.contentsOfDirectory(
                    at: tmpDir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: .skipsHiddenFiles
                )
                for url in contents {
                    guard url.pathExtension == AppConfig.DragDrop.imagePasteExtension else { continue }
                    let attrs = try url.resourceValues(forKeys: [.contentModificationDateKey])
                    let modDate = attrs.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
                    guard modDate < cutoff else { continue }
                    do {
                        try fm.removeItem(at: url)
                        logger.debug("TempJanitor removed stale image: \(url.lastPathComponent)")
                    } catch {
                        logger.debug("TempJanitor could not remove \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            } catch {
                logger.debug("TempJanitor scan failed: \(error.localizedDescription)")
            }
        }
    }

    /// Explicitly register bundled fonts via CoreText.
    /// Called as a static method so it can run before `self` is fully initialized.
    /// `ATSApplicationFontsPath` in Info.plist is unreliable on some macOS versions.
    static func registerBundledFonts() {
        // Xcode flattens Resources/Fonts/ into Resources/ at build time,
        // so search the resource directory directly for font files.
        guard let resourceURL = Bundle.main.resourceURL else {
            logger.warning("Bundle resource URL not found")
            return
        }
        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            logger.warning("Could not list Resources directory: \(error)")
            return
        }
        var registered = 0
        for url in urls where url.pathExtension == "ttf" || url.pathExtension == "otf" {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registered += 1
            } else {
                let desc = error?.takeRetainedValue().localizedDescription ?? "unknown"
                logger.debug("Font \(url.lastPathComponent) note: \(desc)")
            }
        }
        logger.info("Registered \(registered) bundled font(s)")
    }
}
