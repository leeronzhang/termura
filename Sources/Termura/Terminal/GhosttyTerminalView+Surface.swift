import AppKit
import Foundation
import GhosttyKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "GhosttyTerminalView.Surface")

extension GhosttyTerminalView {
    // MARK: - Surface Lifecycle

    func createSurface(app: ghostty_app_t) {
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.scale_factor = Double(scale)

        // Set initial working directory so the shell starts in the project root
        // rather than the process's current directory (typically ~).
        let wdCString: UnsafeMutablePointer<CChar>? = initialWorkingDirectory.flatMap { strdup($0) }
        defer { wdCString.map { free($0) } }
        cfg.working_directory = UnsafePointer(wdCString)

        guard let newSurface = ghostty_surface_new(app, &cfg) else {
            logger.error("ghostty_surface_new failed")
            return
        }
        surface = newSurface

        // Set content scale and initial size immediately.
        ghostty_surface_set_content_scale(newSurface, Double(scale), Double(scale))
        let scaled = convertToBacking(frame.size)
        ghostty_surface_set_size(newSurface, UInt32(scaled.width), UInt32(scaled.height))

        // Tell ghostty which display to sync CVDisplayLink with.
        if let screenNumber = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 {
            ghostty_surface_set_display_id(newSurface, screenNumber)
        }

        // Register PTY output callback (called from IO thread).
        // Uses a file-level function to avoid Swift 6 @MainActor isolation thunk.
        ghostty_surface_set_pty_output_cb(newSurface, Unmanaged.passUnretained(self).toOpaque(), ghosttyPtyOutputCb)

        ghostty_surface_refresh(newSurface)
        setupEventMonitor()
        updateTrackingAreas()
        logger.debug("ghostty surface created")
    }

    /// Release the ghostty surface and event monitor. Idempotent — safe to call
    /// from both processDidExit (natural exit) and LibghosttyEngine.terminate (forced).
    func destroySurface() {
        if let s = surface {
            ghostty_surface_free(s)
            surface = nil
        }
        if let em = eventMonitor {
            NSEvent.removeMonitor(em)
            eventMonitor = nil
        }
        trackingAreas.forEach { removeTrackingArea($0) }
        logger.debug("ghostty surface destroyed")
    }
}
