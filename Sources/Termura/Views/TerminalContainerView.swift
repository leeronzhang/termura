// Exemption: This is the ONLY file permitted to import SwiftTerm in the Views layer.
// The NSViewRepresentable boundary is explicitly required by the architecture.
import AppKit
import OSLog
import SwiftTerm
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalContainerView")

/// NSViewRepresentable wrapper around SwiftTerm's LocalProcessTerminalView.
/// Acts as the bridge between SwiftUI layout and the AppKit terminal renderer.
/// Returns a TerminalDragContainerView so that drag-and-drop is handled by a real
/// NSDraggingDestination override rather than a disconnected Coordinator.
struct TerminalContainerView: NSViewRepresentable {
    let viewModel: TerminalViewModel
    let engine: any TerminalEngine
    let theme: ThemeColors
    /// Value types so SwiftUI diffs trigger updateNSView on change.
    let fontFamily: String
    let fontSize: CGFloat
    /// When true, hitTest returns nil so that NSWindow falls back to the NSHostingView
    /// and SwiftUI gesture targets (backdrop, composer header buttons) receive events.
    var isComposerActive: Bool = false

    func makeNSView(context: Context) -> TerminalDragContainerView {
        let termView = engine.terminalNSView
        termView.autoresizingMask = [.width, .height]
        if let tv = termView as? LocalProcessTerminalView {
            applyTheme(theme, to: tv)
        }
        let container = TerminalDragContainerView(terminalView: termView)
        // Cache NSScroller references once at construction time so updateNSView never
        // traverses subviews. SwiftTerm adds the scroller during its own init and does
        // not remove/re-add it, so the reference remains valid for the view's lifetime.
        container.cacheAndHideScrollers()
        // Seed the font cache so the first updateNSView call skips the redundant font assignment.
        container.lastAppliedFontName = fontFamily
        container.lastAppliedFontSize = fontSize
        container.dragHandler = { [weak viewModel] paths in
            viewModel?.send(paths)
        }
        return container
    }

    func updateNSView(_ container: TerminalDragContainerView, context: Context) {
        container.isPassthrough = isComposerActive
        guard let termView = container.terminalView as? LocalProcessTerminalView else { return }
        // Colors are cheap to set — always apply so theme switches take effect immediately.
        applyColors(theme, to: termView)
        // Font assignment is expensive: SwiftTerm recalculates character dimensions for every cell.
        // Guard to avoid triggering this on every parent re-render (ViewModel observable
        // property changes cause frequent re-renders — without this guard, CPU spikes when idle).
        let fontChanged = container.lastAppliedFontName != fontFamily
            || container.lastAppliedFontSize != fontSize
        if fontChanged {
            applyFont(to: termView)
            container.lastAppliedFontName = fontFamily
            container.lastAppliedFontSize = fontSize
        }
        // Use cached scroller references — O(1) instead of O(n) subview traversal.
        // SwiftTerm may reset isHidden after its own layout pass, so we re-apply each render.
        container.hideCachedScrollers()
    }

    // MARK: - Theme application

    private func applyColors(_ theme: ThemeColors, to view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = NSColor(theme.background)
        view.nativeForegroundColor = NSColor(theme.foreground)
        view.installColors(theme.toSwiftTermColors())
    }

    private func applyFont(to view: LocalProcessTerminalView) {
        let font = NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.font = font
        logger.debug("Terminal font set: \(font.fontName) size=\(fontSize)")
    }

    private func applyTheme(_ theme: ThemeColors, to view: LocalProcessTerminalView) {
        applyColors(theme, to: view)
        applyFont(to: view)
    }

}

// MARK: - TerminalDragContainerView

/// Container NSView wrapping the SwiftTerm terminal view.
/// Implements NSDraggingDestination directly — this is required because NSView subclasses
/// must override drag methods themselves; there is no drag delegate protocol.
///
/// Supports:
///   - File URL drops: shell-escapes the path and sends it to the terminal.
///   - Image drops (PNG/TIFF from screenshots, browsers, Preview): saves a temporary
///     PNG to ~/.termura/tmp/ and sends the escaped path.
@MainActor
final class TerminalDragContainerView: NSView {
    let terminalView: NSView
    var dragHandler: ((String) -> Void)?
    /// Set to true while the composer overlay is visible so that hitTest returns nil,
    /// letting AppKit fall through to NSHostingView and SwiftUI handle events.
    var isPassthrough = false
    /// Last font family/size applied via updateNSView. Guards against SwiftTerm
    /// recalculating character dimensions on every parent view re-render.
    var lastAppliedFontName: String?
    var lastAppliedFontSize: CGFloat = 0
    /// Cached NSScroller subviews found at construction time. SwiftTerm adds its scroller
    /// during init and never removes it, so this reference stays valid for the view's lifetime.
    /// Populated by cacheAndHideScrollers(); used by hideCachedScrollers() on every render.
    private var cachedScrollers: [NSScroller] = []
    // In-flight task debouncing SIGWINCH delivery after a layout change.
    // Prevents the double-resize that occurs when SwiftUI issues a transient
    // wrong-sized layout pass followed immediately by the correct-sized pass.
    // nonisolated(unsafe): deinit is nonisolated; last-reference guarantee makes
    // the access free of data races — no concurrent mutation is possible at deinit time.
    nonisolated(unsafe) private var pendingResizeTask: Task<Void, Never>?

    override func hitTest(_ point: NSPoint) -> NSView? {
        isPassthrough ? nil : super.hitTest(point)
    }

    // Belt-and-suspenders: also block window drag on the container itself,
    // in case a future subview change makes this the hit-tested view.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Scroller cache

    /// Called once in makeNSView after SwiftTerm has fully initialised its subview tree.
    /// Locates all NSScroller instances, hides them, and stores references so that
    /// hideCachedScrollers() can operate in O(1) on subsequent updateNSView calls.
    func cacheAndHideScrollers() {
        cachedScrollers = terminalView.subviews.compactMap { $0 as? NSScroller }
        for scroller in cachedScrollers {
            scroller.isHidden = true
        }
    }

    /// Re-hides the previously cached NSScroller references.
    /// SwiftTerm may reset isHidden during its own layout pass, so this is called
    /// on every updateNSView to keep the scrollers suppressed — cost is O(1).
    func hideCachedScrollers() {
        for scroller in cachedScrollers {
            scroller.isHidden = true
        }
    }

    init(terminalView: NSView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
        registerForDraggedTypes([.fileURL, .URL, .tiff, .png])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("TerminalDragContainerView must be instantiated programmatically, not via Interface Builder")
    }

    deinit {
        pendingResizeTask?.cancel()
    }

    override func layout() {
        super.layout()
        let newBounds = bounds
        guard terminalView.frame != newBounds else { return }
        terminalView.frame = newBounds
        // Debounce SIGWINCH delivery by one frame.
        // SwiftUI issues two layout passes when rebuilding the terminal view tree on a
        // session switch: the first pass fires with a transient wrong size (observed as
        // 2x the final dimensions), the second with the correct size. Without debouncing,
        // layoutSubtreeIfNeeded() sends SIGWINCH at both sizes, causing the terminal to
        // temporarily reflow at the wrong column count. Waiting one frame (16ms) ensures
        // only the final, stable bounds triggers changeWindowSize().
        pendingResizeTask?.cancel()
        pendingResizeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: AppConfig.Terminal.resizeDebounce)
            } catch {
                return
            }
            terminalView.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        let hasFileURL = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
        return (hasFileURL || hasImage) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path.shellEscaped).joined(separator: " ")
            dragHandler?(paths)
            return true
        }
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            do {
                let url = try saveTemporaryAttachmentImage(image)
                dragHandler?(url.path.shellEscaped)
                return true
            } catch {
                logger.error("Failed to save dropped image: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }

}
