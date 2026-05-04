import AppKit
import Foundation
import GhosttyKit
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "LibghosttyEngine")

/// Phase 2 implementation of `TerminalEngine` for the libghostty backend.
///
/// Metal-accelerated rendering via `GhosttyTerminalView`.
/// Raw PTY output flows through the Zig callback → outputStream → AgentStateDetector.
///
/// Surface as a single struct hits the §6.1 file-length budget when every
/// concern lives inline; the engine is therefore split across:
/// - `+PtyStream.swift`: protocol impls for the W2 byte-fan-out / checkpoint surface.
/// - `+SurfaceConfig.swift`: applyTheme / applyFont / updateSurfaceConfig.
/// - `+ScreenAccess.swift`: cursorLineContent / readVisibleScreen / linesNearCursor / scroll.
/// - `+Styled.swift`: structured viewport extraction (pre-existing).
@MainActor
final class LibghosttyEngine: TerminalEngine {
    // MARK: - TerminalEngine conformance

    let outputStream: AsyncStream<TerminalOutputEvent>
    let shellEventsStream: AsyncStream<ShellIntegrationEvent>
    private(set) var state: TerminalLifecycleState = .created
    var isRunning: Bool { state == .running }

    var hasSurface: Bool { ghosttyView.surface != nil }
    let terminalNSView: NSView
    private let sessionID: SessionID
    /// One-to-many fan-out of raw PTY bytes for the harness pty-stream
    /// pump. Constructed once at engine init, shared with the underlying
    /// `GhosttyTerminalView` (whose IO callback feeds it on every byte
    /// chunk). Released via `tap.finishAll()` from `terminate()`.
    /// OWNER: this engine. TEARDOWN: `terminate() → tap.finishAll()`.
    /// TEST: `PtyByteTapTests` covers fan-out / unsubscribe / finishAll;
    /// `LibghosttyEngineTests` covers the wiring here. `internal` (not
    /// `private`) so `LibghosttyEngine+PtyStream.swift` can reach it
    /// for the protocol method implementations.
    let ptyByteTap: PtyByteTap

    // MARK: - Internal

    /// Internal (not private) so `LibghosttyEngine+Styled.swift` can read the
    /// surface for render-state extraction without exposing a public wrapper.
    let ghosttyView: GhosttyTerminalView
    let outputContinuation: AsyncStream<TerminalOutputEvent>.Continuation
    let shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation
    /// Lazily-initialised holder for the per-session GhosttyRenderState +
    /// row/cell iterators used by `readVisibleStyledScreen()`. `nil` until
    /// the first remote screen-frame pull, so non-remote sessions don't pay
    /// the C-side allocation. See `LibghosttyEngine+Styled.swift`.
    var styledExtractor: StyledScreenExtractor?
    /// Tracks the last-applied values so surface config updates always
    /// carry the full state. Consumed by `+SurfaceConfig.swift`.
    var currentFontFamily: String = FontSettings.defaultFamily
    var currentFontSize: CGFloat = FontSettings.defaultTerminalSize
    var currentTheme: ThemeColors = .dark

    /// Optional observer fired once when the underlying child process
    /// exits and the engine moves to `.disposed`. Used by the composition
    /// root to refresh the iOS-visible session list (§3.6 push-on-change)
    /// so a remote client never sees a session whose engine has died.
    /// Optional under §3.3 because non-remote builds (and previews / unit
    /// tests) don't need to plumb a sink — diagnostics-class dependency.
    let onLifecycleChanged: (@MainActor @Sendable () -> Void)?

    // MARK: - Init

    init(
        sessionID: SessionID,
        workingDirectory: String? = nil,
        onLifecycleChanged: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.sessionID = sessionID
        self.onLifecycleChanged = onLifecycleChanged
        // WHY: Terminal output bridges ghostty callbacks into async consumers with bounded buffering.
        // OWNER: LibghosttyEngine owns outputContinuation and shellContinuation for the engine lifetime.
        // TEARDOWN: terminate() finishes both continuations.
        // TEST: Cover output/shell event delivery and shutdown finishing both streams.
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
        // Construct the byte tap before the view so the view's IO
        // callback sees a live tap on the very first frame. The tap is
        // empty (zero subscribers) until the harness router calls
        // `subscribeBytes()`; until then `feedNonisolated` is a no-op.
        let tap = PtyByteTap()
        ptyByteTap = tap
        let view = GhosttyTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            app: app,
            workingDirectory: workingDirectory,
            outputContinuation: outCont,
            shellContinuation: shellCont,
            ptyByteTap: tap
        )
        ghosttyView = view
        terminalNSView = view
        state = .attached

        wireViewCallbacks(view: view)

        state = .running
        logger.debug("LibghosttyEngine created for session \(sessionID.rawValue)")
    }

    /// Connect `GhosttyTerminalView`'s lifecycle callbacks to the engine's
    /// streams. Pulled out of `init` so the constructor stays under the
    /// 50-line function-body budget (§6.1).
    private func wireViewCallbacks(view: GhosttyTerminalView) {
        view.onTitleChanged = { [outputContinuation] title in
            outputContinuation.yield(.titleChanged(title))
        }
        view.onWorkingDirectoryChanged = { [outputContinuation] pwd in
            outputContinuation.yield(.workingDirectoryChanged(pwd))
        }
        view.onProcessExited = { [weak self, outputContinuation] _ in
            guard let self else { return }
            let code = ghosttyView.lastExitCode ?? 0
            outputContinuation.yield(.processExited(code))
            outputContinuation.finish()
            state = .disposed
            // Notify the composition root so the broadcaster re-emits a
            // session list with this dead session filtered out — without
            // it iOS keeps the session in its list and lands on the 30 s
            // timeout fallback the next time the user taps it.
            onLifecycleChanged?()
        }
        // ghostty OSC 133;D → shell integration event
        view.onCommandFinished = { [shellContinuation] exitCode in
            let code: Int? = exitCode == -1 ? nil : Int(exitCode)
            shellContinuation.yield(.executionFinished(exitCode: code))
        }
    }

    // MARK: - TerminalEngine methods

    func send(_ text: String) async {
        guard let surface = ghosttyView.surface else {
            // The remote-control path lands here when the iOS user hits Send
            // for a session whose ghostty surface isn't allocated (window
            // closed, view not yet attached). The PTY process can still be
            // alive (engine.isRunning == true) so RemoteCommandRunner's
            // existing guard doesn't catch it; surface a clear log so the
            // failure mode is recoverable from Console rather than silent.
            logger.warning("LibghosttyEngine.send no-op: surface is nil for session \(sessionID.rawValue)")
            return
        }
        let len = text.utf8CString.count
        guard len > 0 else { return }
        logger.info("LibghosttyEngine.send: \(len - 1) bytes to session \(sessionID.rawValue)")
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(len - 1))
        }
    }

    func pressReturn() async {
        guard let surface = ghosttyView.surface else {
            logger.warning("LibghosttyEngine.pressReturn no-op: surface is nil for session \(sessionID.rawValue)")
            return
        }
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
        _ = (columns, rows)
    }

    func terminate() async {
        guard state != .disposed && state != .exiting else { return }
        let sid = sessionID.rawValue
        logger.debug("Terminating LibghosttyEngine for session \(sid)")
        state = .exiting

        outputContinuation.finish()
        shellContinuation.finish()
        // Finish every pty-byte subscription so the harness router's
        // pump exits cleanly. New `subscribe()` calls after this point
        // get an immediately-finished stream so a late subscriber never
        // hangs awaiting a dead engine. Synchronous because the tap
        // uses an unfair lock for ordering, not an actor.
        ptyByteTap.finishAll()

        // Force ghostty surface destruction; this triggers the child process exit
        // and eventually calls onProcessExited which sets state to .disposed.
        ghosttyView.destroySurface()
    }

    deinit {
        let sid = sessionID.rawValue
        logger.debug("LibghosttyEngine deinit for session \(sid)")
    }
}
