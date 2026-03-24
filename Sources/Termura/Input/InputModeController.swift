import Foundation

/// Controls whether the input area is in editor mode (NSTextView) or raw passthrough.
@MainActor
final class InputModeController: ObservableObject {
    enum Mode: Sendable {
        case editor
        case passthrough
    }

    @Published private(set) var mode: Mode = .editor

    func toggleMode() {
        mode = (mode == .editor) ? .passthrough : .editor
    }

    func switchToEditor() {
        mode = .editor
    }

    func switchToPassthrough() {
        mode = .passthrough
    }
}
