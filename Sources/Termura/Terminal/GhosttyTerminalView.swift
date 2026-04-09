import AppKit
import Foundation
import GhosttyKit
import OSLog
import QuartzCore

private let logger = Logger(subsystem: "com.termura.app", category: "GhosttyTerminalView")

/// NSView backed by a ghostty Metal surface.
///
/// Lifecycle: create → `viewDidMoveToWindow` creates the surface → `processDidExit` tears it down.
/// Register event forwarding callbacks before adding to a window.
@MainActor
final class GhosttyTerminalView: NSView {
    // MARK: - Public callbacks (set by LibghosttyEngine)

    var onTitleChanged: ((String) -> Void)?
    var onWorkingDirectoryChanged: ((String) -> Void)?
    var onCommandFinished: ((Int16) -> Void)?
    var onProcessExited: ((Bool) -> Void)?
    /// Exit code from GHOSTTY_ACTION_SHOW_CHILD_EXITED, set before close_surface_cb fires.
    private(set) var lastExitCode: Int32?
    /// Raw PTY output — io-reader thread yields directly to this continuation (thread-safe).
    /// Set once before IO starts via LibghosttyEngine; never mutated after.
    nonisolated let ptyOutputContinuation: AsyncStream<TerminalOutputEvent>.Continuation
    /// Shell integration events parsed from raw PTY output (OSC 133 A/B/C).
    /// D is handled by ghostty's GHOSTTY_ACTION_COMMAND_FINISHED action.
    nonisolated let shellIntegrationContinuation: AsyncStream<ShellIntegrationEvent>.Continuation

    // MARK: - Surface

    // nonisolated(unsafe): deinit cleanup access
    nonisolated(unsafe) var surface: ghostty_surface_t?
    // nonisolated(unsafe): deinit
    nonisolated(unsafe) var eventMonitor: Any?

    // MARK: - IME / Text Input state (accessed by GhosttyTerminalView+TextInput)

    /// Preedit (marked) text from the input method. Non-empty while composing CJK characters.
    var markedText = NSMutableAttributedString()
    /// Non-nil during keyDown processing; accumulates text from insertText calls triggered
    /// by interpretKeyEvents. Nil at all other times.
    var keyTextAccumulator: [String]?

    // MARK: - Context menu state

    struct ContextMenuActions {
        var onQuoteInComposer: ((String) -> Void)?
        var onAskAboutThis: ((String) -> Void)?
        var onSendToNotes: ((String) -> Void)?
        var onClearTerminal: (() -> Void)?
    }

    /// Callbacks for context menu actions, wired by TerminalAreaView at view-appear time.
    var contextMenuActions = ContextMenuActions()
    /// Caches the selected text at menu-build time so async action handlers read a stable snapshot.
    var menuCachedSelection: String?

    // MARK: - Link hover state

    /// URL string when the mouse hovers over a recognized link. Drives cursor shape.
    var hoverUrl: String? {
        didSet {
            if (hoverUrl != nil) != (oldValue != nil) {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    // MARK: - Init / Deinit

    /// Initial working directory for the shell spawned by ghostty.
    /// Stored until createSurface where it is passed into the surface config.
    let initialWorkingDirectory: String?

    /// Create the view and ghostty surface.
    /// The view provides its own CAMetalLayer via makeBackingLayer (layer-backed mode).
    /// ghostty's Metal renderer renders INTO this layer.
    init(
        frame: NSRect,
        app: ghostty_app_t,
        workingDirectory: String? = nil,
        outputContinuation: AsyncStream<TerminalOutputEvent>.Continuation,
        shellContinuation: AsyncStream<ShellIntegrationEvent>.Continuation
    ) {
        initialWorkingDirectory = workingDirectory
        ptyOutputContinuation = outputContinuation
        shellIntegrationContinuation = shellContinuation
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        createSurface(app: app)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(frame:app:)")
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let s = surface {
            // ghostty_surface_free must be called on main thread.
            // Pointer is captured by value for the task.
            Task { @MainActor in
                ghostty_surface_free(s)
            }
        }
        logger.debug("GhosttyTerminalView deinit")
    }

    /// Provide a CAMetalLayer so Core Animation knows this view uses Metal from the start.
    /// This avoids the dispatch_assert_queue(main) crash that occurs when ghostty's
    /// renderer thread reads CALayer properties (bounds, contentsScale) on a
    /// Core-Animation-managed backing layer.
    override func makeBackingLayer() -> CALayer {
        let metalLayer = CAMetalLayer()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = false
        return metalLayer
    }

    // MARK: - Process exit (called by GhosttyAppContext)

    /// Record the child exit code before close_surface_cb fires.
    func recordChildExitCode(_ code: UInt32) {
        lastExitCode = Int32(bitPattern: code)
    }

    func processDidExit(processAlive: Bool) {
        onProcessExited?(processAlive)
        destroySurface()
    }

    // MARK: - Cursor shape

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor = hoverUrl != nil ? .pointingHand : .iBeam
        addCursorRect(visibleRect, cursor: cursor)
    }

    // MARK: - Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }
        let scaled = convertToBacking(newSize)
        ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        ghostty_surface_set_content_scale(surface, scale, scale)
        let scaled = convertToBacking(frame.size)
        ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
    }

    // MARK: - Focus

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { ghostty_surface_set_focus(surface, true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { ghostty_surface_set_focus(surface, false) }
        return result
    }

    // MARK: - Screen content (used by LibghosttyEngine for cursor/scroll)

    func readVisibleText() -> String {
        guard let surface else { return "" }
        var text = ghostty_text_s()
        let sel = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0
            ),
            rectangle: false
        )
        guard ghostty_surface_read_text(surface, sel, &text) else { return "" }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }
}
