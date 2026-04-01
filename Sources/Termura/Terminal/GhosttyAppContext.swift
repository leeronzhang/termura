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
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification,
            object: nil)
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
    nonisolated(unsafe) private var tickScheduled = false

    nonisolated func scheduleTick() {
        tickLock.lock()
        defer { tickLock.unlock() }
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
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

    // MARK: - Static C Callbacks (nonisolated: called from ghostty threads)

    // Wakeup: userdata = app userdata (GhosttyAppContext).
    // Fires thousands of times/sec from IO thread — coalesced via scheduleTick().
    nonisolated static func cWakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let ctx = Unmanaged<GhosttyAppContext>.fromOpaque(userdata).takeUnretainedValue()
        ctx.scheduleTick()
    }

    // Action: routes UI actions to main actor.
    // ghostty's renderer thread manages its own draw loop via CVDisplayLink —
    // the macOS apprt does NOT handle GHOSTTY_ACTION_RENDER in the action callback.
    @discardableResult
    nonisolated static func cAction(
        _ app: ghostty_app_t,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        // Surface-targeted UI actions need the main actor.
        if target.tag == GHOSTTY_TARGET_SURFACE,
           let surface = target.target.surface {
            Task { @MainActor in
                Self.handleSurfaceAction(surface: surface, action: action)
            }
            return true
        }

        // App-targeted actions that Termura handles.
        switch action.tag {
        case GHOSTTY_ACTION_OPEN_URL:
            Task { @MainActor in
                Self.openURL(action.action.open_url)
            }
            return true
        default:
            return false
        }
    }

    @MainActor
    private static func handleSurfaceAction(surface: ghostty_surface_t, action: ghostty_action_s) {
        guard let ud = ghostty_surface_userdata(surface) else { return }
        let view = Unmanaged<GhosttyTerminalView>.fromOpaque(ud).takeUnretainedValue()

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            guard let rawTitle = action.action.set_title.title,
                  let title = String(cString: rawTitle, encoding: .utf8) else { return }
            view.onTitleChanged?(title)

        case GHOSTTY_ACTION_PWD:
            guard let rawPwd = action.action.pwd.pwd else { return }
            view.onWorkingDirectoryChanged?(String(cString: rawPwd))

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            view.onCommandFinished?(action.action.command_finished.exit_code)

        case GHOSTTY_ACTION_OPEN_URL:
            openURL(action.action.open_url)

        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
            let link = action.action.mouse_over_link
            if link.len > 0, let ptr = link.url {
                let data = Data(bytes: ptr, count: Int(link.len))
                view.hoverUrl = String(data: data, encoding: .utf8)
            } else {
                view.hoverUrl = nil
            }

        default:
            break
        }
    }

    // MARK: - URL opening

    /// Open a URL or file path detected by ghostty's link recognizer.
    /// URLs with schemes open in the default handler; bare paths open as files.
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

        NSWorkspace.shared.open(url)
    }
}
