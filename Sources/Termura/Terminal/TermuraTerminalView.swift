import AppKit
import SwiftTerm

/// Subclass of `LocalProcessTerminalView` that intercepts raw PTY bytes
/// before they are fed into SwiftTerm's ANSI renderer.
///
/// Overrides the `open` method `dataReceived(slice:)` — the single point
/// where all PTY output passes through — to forward each batch of bytes
/// to `onDataReceived` before delegating to `super` for normal rendering.
///
/// This is the only public hook SwiftTerm exposes for raw output interception
/// without reimplementing PTY management from scratch.
@MainActor
final class TermuraTerminalView: LocalProcessTerminalView {
    /// Called synchronously on the main queue for every PTY read batch.
    /// @MainActor ensures this closure is only set and invoked on the main thread.
    var onDataReceived: (@MainActor (ArraySlice<UInt8>) -> Void)?

    // MARK: - Force-selection state

    /// True while the user is performing an Option+drag forced-selection gesture.
    /// Tracks state across the mouseDown -> mouseDragged -> mouseUp sequence.
    private var isOptionForceSelecting = false
    /// Saved value of `allowMouseReporting` before forced-selection begins,
    /// restored on mouseUp so the PTY mouse reporting contract is preserved.
    private var savedMouseReporting = true

    override func dataReceived(slice: ArraySlice<UInt8>) {
        // Process through SwiftTerm's ANSI/cursor engine FIRST so the buffer
        // reflects the updated screen state before we notify consumers.
        super.dataReceived(slice: slice)
        onDataReceived?(slice)
    }

    // MARK: - Option+drag forced text selection (local event monitor)

    /// Holding Option while clicking bypasses terminal mouse reporting so that
    /// the user can always drag-select text regardless of whether the running
    /// process (e.g. Claude Code) has enabled mouse event forwarding.
    ///
    /// This matches the behaviour of iTerm2 and Terminal.app.
    ///
    /// SwiftTerm's mouseDown/mouseUp are declared `public` (not `open`), so
    /// Swift 6 forbids overriding them outside the module. An NSEvent local
    /// monitor fires before the responder chain, giving us the same intercept
    /// point without subclass overrides.
    nonisolated(unsafe) private var mouseEventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMouseMonitor()
        } else {
            removeMouseMonitor()
        }
    }

    deinit {
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func installMouseMonitor() {
        removeMouseMonitor()
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    private func removeMouseMonitor() {
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard event.window === window else { return }

        switch event.type {
        case .leftMouseDown:
            // Clean up any leaked state from a prior cancelled drag.
            if isOptionForceSelecting {
                allowMouseReporting = savedMouseReporting
                isOptionForceSelecting = false
            }
            if event.modifierFlags.contains(.option) {
                isOptionForceSelecting = true
                savedMouseReporting = allowMouseReporting
                // Disable reporting so super.mouseDown does not forward the click
                // to the PTY, and super.mouseDragged falls through to SwiftTerm's
                // text-selection logic instead.
                allowMouseReporting = false
            }
        case .leftMouseUp:
            guard isOptionForceSelecting else { return }
            let savedValue = savedMouseReporting
            // Clear flag now so a rapid next mouseDown sees clean state.
            isOptionForceSelecting = false
            // Defer allowMouseReporting restoration until after super.mouseUp
            // has processed the event — prevents a spurious PTY mouse-up event
            // being sent while reporting was disabled for this drag gesture.
            Task { @MainActor [weak self] in
                self?.allowMouseReporting = savedValue
            }
        default:
            break
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let copyItem = menu.addItem(
            withTitle: "Copy",
            action: #selector(copy(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self

        let pasteItem = menu.addItem(
            withTitle: "Paste",
            action: #selector(paste(_:)),
            keyEquivalent: ""
        )
        pasteItem.target = self

        menu.addItem(.separator())

        let selectAllItem = menu.addItem(
            withTitle: "Select All",
            action: #selector(selectAll(_:)),
            keyEquivalent: ""
        )
        selectAllItem.target = self

        menu.addItem(.separator())

        let clearItem = menu.addItem(
            withTitle: "Clear",
            action: #selector(performClearScreen),
            keyEquivalent: ""
        )
        clearItem.target = self

        return menu
    }

    @objc private func performClearScreen() {
        send(txt: "clear\n")
    }
}
