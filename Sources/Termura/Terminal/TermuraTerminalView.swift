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
    /// Called when the user triggers a context action (Quote / Ask) from the right-click menu.
    /// Receives the pre-formatted composer prefill string. Always invoked on the main actor.
    var onContextAction: (@MainActor (String) -> Void)?
    /// Called when the user chooses "Send to Notes" from the right-click menu.
    /// Receives the raw selected text. Always invoked on the main actor.
    var onSendToNotes: (@MainActor (String) -> Void)?

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

    // Holding Option while clicking bypasses terminal mouse reporting so that
    // the user can always drag-select text regardless of whether the running
    // process (e.g. Claude Code) has enabled mouse event forwarding.
    // This matches the behaviour of iTerm2 and Terminal.app.
    // SwiftTerm's mouseDown/mouseUp are declared `public` (not `open`), so
    // Swift 6 forbids overriding them outside the module. An NSEvent local
    // monitor fires before the responder chain, giving us the same intercept
    // point without subclass overrides.
    private var mouseEventMonitor: Any?

    // Prevent isMovableByWindowBackground from intercepting mouse drags inside
    // the terminal — without this, clicking and dragging in non-fullscreen mode
    // moves the window instead of selecting text.
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMouseMonitor()
        } else {
            removeMouseMonitor()
        }
    }

    private func installMouseMonitor() {
        removeMouseMonitor()
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event -> NSEvent? in
            guard let self else { return event }
            return self.handleMouseEvent(event)
        }
    }

    private func removeMouseMonitor() {
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
        }
    }

    private func handleMouseEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }

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
            return event
        case .leftMouseUp:
            if isOptionForceSelecting {
                let savedValue = savedMouseReporting
                // Clear flag now so a rapid next mouseDown sees clean state.
                isOptionForceSelecting = false
                // Defer allowMouseReporting restoration until after super.mouseUp
                // has processed the event — prevents a spurious PTY mouse-up event
                // being sent while reporting was disabled for this drag gesture.
                Task { @MainActor [weak self] in
                    self?.allowMouseReporting = savedValue
                }
                return event
            }
            // Cmd+click: open URL at the clicked terminal cell.
            if event.modifierFlags.contains(.command) {
                let point = convert(event.locationInWindow, from: nil)
                if bounds.contains(point), let (col, row) = visibleCell(at: point) {
                    if let url = osc8URL(col: col, row: row) ?? plainTextURL(col: col, row: row) {
                        openTerminalURL(url)
                        return nil  // consume — URL was opened
                    }
                }
            }
            return event
        default:
            return event
        }
    }

    // MARK: - Context menu

    /// Cached selected text captured at menu-build time.
    /// Right-click does not clear the SwiftTerm selection, but by the time a menu item
    /// fires its action the selection may already be gone — so we snapshot it here.
    private var menuCachedSelection: String = ""

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(performClearScreen):
            return true
        case #selector(performQuote), #selector(performAsk), #selector(performSendToNotes):
            return !menuCachedSelection.isEmpty
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuCachedSelection = getSelection() ?? ""
        let hasSelection = !menuCachedSelection.isEmpty

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

        if hasSelection {
            menu.addItem(.separator())

            let quoteItem = menu.addItem(
                withTitle: "Quote in Composer",
                action: #selector(performQuote),
                keyEquivalent: ""
            )
            quoteItem.target = self

            let askItem = menu.addItem(
                withTitle: "Ask About This",
                action: #selector(performAsk),
                keyEquivalent: ""
            )
            askItem.target = self

            let sendToNotesItem = menu.addItem(
                withTitle: "Send to Notes",
                action: #selector(performSendToNotes),
                keyEquivalent: ""
            )
            sendToNotesItem.target = self
        }

        return menu
    }

    @objc private func performClearScreen() {
        send(txt: "clear\n")
    }

    @objc private func performQuote() {
        let text = formatAsQuote(menuCachedSelection)
        guard !text.isEmpty else { return }
        onContextAction?(text)
    }

    @objc private func performAsk() {
        let text = formatAsQuote(menuCachedSelection) + "Question: "
        guard !menuCachedSelection.isEmpty else { return }
        onContextAction?(text)
    }

    @objc private func performSendToNotes() {
        guard !menuCachedSelection.isEmpty else { return }
        onSendToNotes?(menuCachedSelection)
    }

    /// Prefixes each line of `text` with "> " and appends two newlines.
    /// Trims leading/trailing whitespace so the quote block is clean.
    private func formatAsQuote(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let quoted = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        return quoted + "\n\n"
    }
}
