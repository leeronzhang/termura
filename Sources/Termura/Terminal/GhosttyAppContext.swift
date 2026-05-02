import AppKit
import Foundation
import GhosttyKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "GhosttyAppContext")

/// Manages the process-wide `ghostty_app_t` singleton.
///
/// All ghostty C API calls must happen on the main thread. This class is `@MainActor`
/// to enforce that constraint. Static C callbacks dispatch back to main via Task.
@MainActor
final class GhosttyAppContext {
    static let shared = GhosttyAppContext()

    private(set) var app: ghostty_app_t?
    // Held so ghostty_config_free can be called on teardown.
    private var config: ghostty_config_t?

    // Singleton — lives for the entire process, deinit never runs.
    private init() {
        boot()
    }

    // MARK: - Boot

    private func boot() {
        guard initGhosttyGlobal() else { return }
        guard let cfg = createConfig() else { return }
        config = cfg
        guard let newApp = createApp(config: cfg) else { return }
        app = newApp
        registerNotifications()
        logger.info("GhosttyAppContext ready")
    }

    private func initGhosttyGlobal() -> Bool {
        // ghostty_init returns 0 on success. We compare against the literal
        // here rather than a named constant — ghostty.h's previous
        // `GHOSTTY_SUCCESS` macro was removed to avoid colliding with the
        // typed `GhosttyResult.GHOSTTY_SUCCESS` enumerator from vt/types.h.
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == 0 else {
            logger.error("ghostty_init failed with code \(result)")
            return false
        }
        logger.info("ghostty_init succeeded")
        return true
    }

    private func createConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else {
            logger.error("ghostty_config_new failed")
            return nil
        }
        // Load user's ghostty config (if any), then override with Termura settings.
        ghostty_config_load_default_files(cfg)
        ghostty_config_load_recursive_files(cfg)
        injectTermuraDefaults(into: cfg)
        ghostty_config_finalize(cfg)
        logger.info("ghostty_config_new succeeded")
        return cfg
    }

    /// Inject Termura's font, color, and shell-integration settings into the ghostty config.
    /// Written as a temp file because ghostty has no config_set API.
    private func injectTermuraDefaults(into cfg: ghostty_config_t) {
        let bg = ThemeColors.dark.background.hexRGB
        let fg = ThemeColors.dark.foreground.hexRGB
        let fontSettings = FontSettings()
        let font = fontSettings.terminalFontFamily
        let size = Int(fontSettings.terminalFontSize)
        let config = """
        font-family = \(font)
        font-size = \(size)
        background = \(bg)
        foreground = \(fg)
        shell-integration = none
        """
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-ghostty-\(UUID().uuidString).conf")
        do {
            try config.write(to: tmpURL, atomically: true, encoding: .utf8)
            defer {
                do { try FileManager.default.removeItem(at: tmpURL) } catch {
                    logger.error("Failed to clean up ghostty config tmp: \(error.localizedDescription)")
                }
            }
            tmpURL.path.withCString { path in
                ghostty_config_load_file(cfg, path)
            }
        } catch {
            logger.error("Failed to write ghostty config override: \(error.localizedDescription)")
        }
    }

    private func createApp(config: ghostty_config_t) -> ghostty_app_t? {
        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: ghosttyWakeupCb,
            action_cb: ghosttyActionCb,
            read_clipboard_cb: ghosttyReadClipboardCb,
            confirm_read_clipboard_cb: ghosttyConfirmReadClipboardCb,
            write_clipboard_cb: ghosttyWriteClipboardCb,
            close_surface_cb: ghosttyCloseSurfaceCb
        )
        guard let newApp = ghostty_app_new(&runtime, config) else {
            logger.error("ghostty_app_new failed")
            return nil
        }
        ghostty_app_set_focus(newApp, NSApp.isActive)
        return newApp
    }

    private func registerNotifications() {
        // WHY: Ghostty focus state must stay aligned with NSApplication active/inactive transitions.
        // OWNER: GhosttyAppContext registers itself as the NotificationCenter observer.
        // TEARDOWN: deinit removes self from NotificationCenter.
        // TEST: Cover app activate/resign notifications updating ghostty_app_set_focus.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func appBecameActive() {
        guard let app else { return }
        ghostty_app_set_focus(app, true)
    }

    @objc private func appResignedActive() {
        guard let app else { return }
        ghostty_app_set_focus(app, false)
    }

    // MARK: - Tick (coalesced)

    // Wakeup fires thousands of times/sec from the IO thread. Coalesce so at most
    // one ghostty_app_tick is pending on the main queue at any time.
    private let tickLock = NSLock()
    // nonisolated(unsafe): deinit
    private nonisolated(unsafe) var tickScheduled = false

    nonisolated func scheduleTick() {
        tickLock.lock()
        defer { tickLock.unlock() }
        guard !tickScheduled else { return }
        tickScheduled = true
        Task { @MainActor [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        tickLock.lock()
        tickScheduled = false
        tickLock.unlock()
        guard let app else { return }
        ghostty_app_tick(app)
    }

    // MARK: - URL opening

    /// Set by `ProjectCoordinator` when opening a project. When non-nil, terminal
    /// link clicks are routed through this router instead of going directly to NSWorkspace.
    /// Static because GhosttyAppContext is a process-wide singleton bridged to C callbacks.
    static var linkRouter: (any LinkRouterProtocol)?

    /// Working directory used for resolving relative paths in terminal links.
    /// Updated by ProjectCoordinator when the active project changes.
    static var currentWorkingDirectory: String = AppConfig.Paths.homeDirectory

    /// Open a URL or file path detected by ghostty's link recognizer.
    /// Routes through LinkRouter when set; falls back to NSWorkspace otherwise.
    @MainActor
    static func openURL(_ urlAction: ghostty_action_open_url_s) {
        guard urlAction.len > 0, let ptr = urlAction.url else { return }
        let data = Data(bytes: ptr, count: Int(urlAction.len))
        guard let rawURL = String(data: data, encoding: .utf8) else { return }

        let url: URL
        if let candidate = URL(string: rawURL), candidate.scheme != nil {
            url = candidate
        } else {
            let expanded = NSString(string: rawURL).standardizingPath
            url = URL(filePath: expanded)
        }

        let forceExternal = NSEvent.modifierFlags.contains(.option)

        if let router = linkRouter {
            router.route(url: url, workingDirectory: currentWorkingDirectory, forceExternal: forceExternal)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
