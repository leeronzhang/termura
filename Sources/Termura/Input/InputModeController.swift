import Foundation

/// Controls whether the input area is in editor mode (NSTextView) or raw passthrough.
@Observable
@MainActor
final class InputModeController {
    enum Mode: Sendable {
        case editor
        case passthrough
    }

    private(set) var mode: Mode = .passthrough

    func switchToEditor() {
        mode = .editor
    }

    func switchToPassthrough() {
        mode = .passthrough
    }
}
