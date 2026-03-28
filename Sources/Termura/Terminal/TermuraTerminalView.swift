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

    override func dataReceived(slice: ArraySlice<UInt8>) {
        // Process through SwiftTerm's ANSI/cursor engine FIRST so the buffer
        // reflects the updated screen state before we notify consumers.
        super.dataReceived(slice: slice)
        onDataReceived?(slice)
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
