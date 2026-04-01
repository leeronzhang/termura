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
    var isRunning = false
    let terminalNSView: NSView

    // MARK: - Internal

    private let ghosttyView: GhosttyTerminalView
    private let outputContinuation: AsyncStream<TerminalOutputEvent>.Continuation
    private let shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation
    /// Tracks the last-applied values so surface config updates always carry the full state.
    private var currentFontFamily: String = FontSettings.defaultFamily
    private var currentFontSize: CGFloat = FontSettings.defaultTerminalSize
    private var currentTheme: ThemeColors = .dark

    // MARK: - Init

    init(sessionID: SessionID, workingDirectory: String? = nil) {
        let (outStream, outCont) = AsyncStream.makeStream(
            of: TerminalOutputEvent.self,
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        outputStream = outStream
        outputContinuation = outCont

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

        // Wire view callbacks → output stream
        view.onTitleChanged = { [outCont] title in
            outCont.yield(.titleChanged(title))
        }
        view.onWorkingDirectoryChanged = { [outCont] pwd in
            outCont.yield(.workingDirectoryChanged(pwd))
        }
        view.onProcessExited = { [outCont] _ in
            outCont.yield(.processExited(0))
            outCont.finish()
        }
        // ghostty OSC 133;D → shell integration event
        view.onCommandFinished = { [shellCont] exitCode in
            let code: Int? = exitCode == -1 ? nil : Int(exitCode)
            shellCont.yield(.executionFinished(exitCode: code))
        }

        isRunning = true
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

    func sendBytes(_ data: Data) async {
        guard let surface = ghosttyView.surface, !data.isEmpty else { return }
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            // ghostty_surface_text takes a UTF-8 C string; raw bytes routed via text API.
            ghostty_surface_text(surface, ptr.assumingMemoryBound(to: CChar.self), UInt(data.count))
        }
    }

    func resize(columns: UInt16, rows: UInt16) async {
        // ghostty manages its own columns/rows from the view frame size.
    }

    func terminate() async {
        isRunning = false
        outputContinuation.finish()
        shellContinuation.finish()
    }

    func cursorLineContent() -> String? {
        let lines = ghosttyView.readVisibleText().split(separator: "\n", omittingEmptySubsequences: false)
        return lines.last { !$0.allSatisfy(\.isWhitespace) }.map(String.init)
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
        logger.debug("Surface config updated: font=\(currentFontFamily) \(Int(currentFontSize))pt")
    }
}
