import Foundation
import GhosttyKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "LibghosttyEngine.SurfaceConfig")

extension LibghosttyEngine {
    func applyTheme(_ theme: ThemeColors) {
        currentTheme = theme
        updateSurfaceConfig()
    }

    func applyFont(family: String, size: CGFloat) {
        currentFontFamily = family
        currentFontSize = size
        updateSurfaceConfig()
    }

    /// Builds a full Termura config overlay (font + theme + shell-integration)
    /// and pushes it to the surface. `ghostty_surface_update_config` replaces
    /// the entire config, so every call must carry all overrides to avoid
    /// resetting unrelated settings to defaults.
    func updateSurfaceConfig() {
        guard let surface = ghosttyView.surface else { return }
        guard let cfg = ghostty_config_new() else {
            logger.error("updateSurfaceConfig: ghostty_config_new failed")
            return
        }
        defer { ghostty_config_free(cfg) }

        let configString = """
        font-family = \(currentFontFamily)
        font-size = \(Int(currentFontSize))
        background = \(currentTheme.background.hexRGB)
        foreground = \(currentTheme.foreground.hexRGB)
        shell-integration = none
        """
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-ghostty-\(UUID().uuidString).conf")
        do {
            try configString.write(to: tmpURL, atomically: true, encoding: .utf8)
            defer {
                do { try FileManager.default.removeItem(at: tmpURL) } catch {
                    logger.error("updateSurfaceConfig: failed to clean up tmp: \(error.localizedDescription)")
                }
            }
            tmpURL.path.withCString { path in
                ghostty_config_load_file(cfg, path)
            }
        } catch {
            logger.error("updateSurfaceConfig: failed to write tmp config: \(error.localizedDescription)")
            return
        }
        ghostty_config_finalize(cfg)
        ghostty_surface_update_config(surface, cfg)
        let fontFamily = currentFontFamily
        let fontSize = currentFontSize
        logger.debug("Surface config updated: font=\(fontFamily) \(Int(fontSize))pt")
    }
}
