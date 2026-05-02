import AppKit
import Foundation
import GhosttyKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "LibghosttyEngine")

/// Phase 2 implementation of `TerminalEngine` for the libghostty backend.
///
/// Metal-accelerated rendering via `GhosttyTerminalView`.
/// Raw PTY output flows through the Zig callback → outputStream → AgentStateDetector.
@MainActor
final class LibghosttyEngine: TerminalEngine {
    // MARK: - TerminalEngine conformance

    let outputStream: AsyncStream<TerminalOutputEvent>
    let shellEventsStream: AsyncStream<ShellIntegrationEvent>
    private(set) var state: TerminalLifecycleState = .created
    var isRunning: Bool { state == .running }
    let terminalNSView: NSView
    private let sessionID: SessionID

    // MARK: - Internal

    /// Internal (not private) so `LibghosttyEngine+Styled.swift` can read the
    /// surface for render-state extraction without exposing a public wrapper.
    let ghosttyView: GhosttyTerminalView
    private let outputContinuation: AsyncStream<TerminalOutputEvent>.Continuation
    private let shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation
    /// Lazily-initialised holder for the per-session GhosttyRenderState +
    /// row/cell iterators used by `readVisibleStyledScreen()`. `nil` until
    /// the first remote screen-frame pull, so non-remote sessions don't pay
    /// the C-side allocation. See `LibghosttyEngine+Styled.swift`.
    var styledExtractor: StyledScreenExtractor?
    /// Tracks the last-applied values so surface config updates always carry the full state.
    private var currentFontFamily: String = FontSettings.defaultFamily
    private var currentFontSize: CGFloat = FontSettings.defaultTerminalSize
    private var currentTheme: ThemeColors = .dark

    // MARK: - Init

    init(sessionID: SessionID, workingDirectory: String? = nil) {
        self.sessionID = sessionID
        // WHY: Terminal output must be bridged from ghostty callbacks into async consumers with bounded buffering.
        // OWNER: LibghosttyEngine owns outputContinuation and shellContinuation for the engine lifetime.
        // TEARDOWN: deinit/close paths finish the continuations when the engine is released.
        // TEST: Cover output/shell event delivery and shutdown finishing both streams.
        let (outStream, outCont) = AsyncStream.makeStream(
            of: TerminalOutputEvent.self,
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        outputStream = outStream
        outputContinuation = outCont

        // WHY: Shell integration events follow the same lifecycle as terminal output and need their own stream.
        // OWNER: LibghosttyEngine owns shellContinuation for the engine lifetime.
        // TEARDOWN: deinit/close paths finish the shell stream when the engine is released.
        // TEST: Cover shell integration event delivery and shutdown finishing the stream.
        let (shellStream, shellCont) = AsyncStream.makeStream(
            of: ShellIntegrationEvent.self,
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        shellEventsStream = shellStream
        shellContinuation = shellCont

        guard let app = GhosttyAppContext.shared.app else {
            preconditionFailure("GhosttyAppContext has no app at engine init")
        }
        let view = GhosttyTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            app: app,
            workingDirectory: workingDirectory,
            outputContinuation: outCont,
            shellContinuation: shellCont
        )
        ghosttyView = view
        terminalNSView = view
        state = .attached

        // Wire view callbacks → output stream
        view.onTitleChanged = { [outCont] title in
            outCont.yield(.titleChanged(title))
        }
        view.onWorkingDirectoryChanged = { [outCont] pwd in
            outCont.yield(.workingDirectoryChanged(pwd))
        }
        view.onProcessExited = { [weak self, outCont] _ in
            guard let self else { return }
            let code = ghosttyView.lastExitCode ?? 0
            outCont.yield(.processExited(code))
            outCont.finish()
            state = .disposed
        }
        // ghostty OSC 133;D → shell integration event
        view.onCommandFinished = { [shellCont] exitCode in
            let code: Int? = exitCode == -1 ? nil : Int(exitCode)
            shellCont.yield(.executionFinished(exitCode: code))
        }

        state = .running
        logger.debug("LibghosttyEngine created for session \(sessionID.rawValue)")
    }

    // MARK: - TerminalEngine methods

    func send(_ text: String) async {
        guard let surface = ghosttyView.surface else { return }
        let len = text.utf8CString.count
        guard len > 0 else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(len - 1))
        }
    }

    func pressReturn() async {
        guard let surface = ghosttyView.surface else { return }
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.keycode = 36
        key.mods = GHOSTTY_MODS_NONE
        key.composing = false
        key.unshifted_codepoint = 0x0D
        key.text = nil
        _ = ghostty_surface_key(surface, key)
        key.action = GHOSTTY_ACTION_RELEASE
        _ = ghostty_surface_key(surface, key)
    }

    func sendBytes(_ data: Data) async {
        guard let surface = ghosttyView.surface, !data.isEmpty else { return }
        // The `ghostty_surface_text` API is text-oriented and assumes valid UTF-8,
        // making it unsafe for raw hex, control bytes, or NUL separated payloads.
        // We leverage Ghostty's binding action engine ("text:\xNN...") to bypass
        // string interpretation and explicitly force the PTY to receive the raw bytes.
        var actionStr = "text:"
        for byte in data {
            actionStr.append(String(format: "\\x%02x", byte))
        }
        actionStr.withCString { ptr in
            _ = ghostty_surface_binding_action(surface, ptr, UInt(actionStr.utf8.count))
        }
    }

    func resize(columns: UInt16, rows: UInt16) async {
        // ghostty manages its own columns/rows from the view frame size.
    }

    func terminate() async {
        guard state != .disposed && state != .exiting else { return }
        let sid = sessionID.rawValue
        logger.debug("Terminating LibghosttyEngine for session \(sid)")
        state = .exiting

        outputContinuation.finish()
        shellContinuation.finish()

        // Force ghostty surface destruction; this triggers the child process exit
        // and eventually calls onProcessExited which sets state to .disposed.
        ghosttyView.destroySurface()

        // If the callback haven't fired yet, we wait up to a timeout or just proceed.
        // For now, destroySurface is largely synchronous in its C-level call.
    }

    deinit {
        let sid = sessionID.rawValue
        logger.debug("LibghosttyEngine deinit for session \(sid)")
    }

    func cursorLineContent() -> String? {
        let lines = ghosttyView.readVisibleText().split(separator: "\n", omittingEmptySubsequences: false)
        return lines.last { !$0.allSatisfy(\.isWhitespace) }.map(String.init)
    }

    func readVisibleScreen() -> TerminalScreenSnapshot? {
        guard let surface = ghosttyView.surface else { return nil }
        let size = ghostty_surface_size(surface)
        let lines = ghosttyView.readVisibleText()
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return TerminalScreenSnapshot(rows: Int(size.rows), cols: Int(size.columns), lines: lines)
    }

    func linesNearCursor(above count: Int) -> [String] {
        let all = ghosttyView.readVisibleText().split(separator: "\n", omittingEmptySubsequences: false)
        guard !all.isEmpty else { return [] }
        let start = max(0, all.count - count - 1)
        return all[start...].map(String.init)
    }

    func currentScrollLine() -> Int {
        // TODO: expose ghostty scroll position via C API
        0
    }

    func scrollToLine(_ line: Int) async {
        // TODO: expose ghostty scroll via C API
    }

    var supportsScrollbackNavigation: Bool { false }

    func applyTheme(_ theme: ThemeColors) {
        currentTheme = theme
        updateSurfaceConfig()
    }

    func applyFont(family: String, size: CGFloat) {
        currentFontFamily = family
        currentFontSize = size
        updateSurfaceConfig()
    }

    // MARK: - Ghostty config update

    /// Builds a full Termura config overlay (font + theme + shell-integration) and pushes
    /// it to the surface. ghostty_surface_update_config replaces the entire config, so
    /// every call must carry all overrides to avoid resetting unrelated settings to defaults.
    private func updateSurfaceConfig() {
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
