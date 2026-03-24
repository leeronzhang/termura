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
final class TermuraTerminalView: LocalProcessTerminalView {
    /// Called synchronously on the main queue for every PTY read batch.
    /// Captures only `Sendable` types so it is safe to hold across actor boundaries.
    var onDataReceived: ((ArraySlice<UInt8>) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        // Process through SwiftTerm's ANSI/cursor engine FIRST so the buffer
        // reflects the updated screen state before we notify consumers.
        super.dataReceived(slice: slice)
        onDataReceived?(slice)
    }
}
