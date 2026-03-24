import AppKit
import SwiftUI

/// Shared reference that lets TerminalAreaView's NSEvent monitor find the live EditorTextView
/// without a retain cycle. Set once in makeNSView; read by the key-routing logic.
final class EditorViewHandle {
    weak var textView: EditorTextView?
}

/// NSViewRepresentable wrapper around EditorTextView.
/// Bridges SwiftUI layout with the AppKit NSTextView editor.
struct EditorInputView: NSViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel
    /// Shared handle so callers can obtain the underlying NSTextView for focus management.
    let viewHandle: EditorViewHandle

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView()
        let scrollView = buildScrollView(around: textView)
        configureTextView(textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        // Sync viewModel text → NSTextView, guarding against feedback loops
        if textView.string != viewModel.currentText {
            context.coordinator.isSyncing = true
            textView.string = viewModel.currentText
            context.coordinator.isSyncing = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Construction helpers

    private func buildScrollView(around textView: EditorTextView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // Use the NSTextView's built-in TextKit stack as-is; do NOT replace the layout manager.
        textView.minSize = NSSize(width: 0, height: AppConfig.UI.editorMinHeightPoints)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }

    private func configureTextView(_ textView: EditorTextView, coordinator: Coordinator) {
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.placeholderString = "输入命令，Shift+Enter 换行，↑↓ 历史"
        textView.delegate = coordinator

        // Register in handle so TerminalAreaView's key-routing monitor can find us
        viewHandle.textView = textView

        textView.submitHandler = { [weak coordinator] text in
            coordinator?.handleSubmit(text)
        }
        textView.newlineHandler = { [weak coordinator] in
            coordinator?.handleNewline()
        }
        textView.historyNavigationHandler = { [weak coordinator] isUp in
            coordinator?.handleHistory(previous: isUp)
        }
        textView.controlSequenceHandler = { [weak coordinator] seq in
            coordinator?.handleControlSequence(seq)
        }

        textView.drawsBackground = true
        textView.backgroundColor = .editorInputBackground
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
    }
}

// MARK: - NSColor helpers

private extension NSColor {
    static var editorInputBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.13, alpha: 1)
                : NSColor(white: 0.97, alpha: 1)
        }
    }
}

// MARK: - Coordinator

extension EditorInputView {
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let viewModel: EditorViewModel
        var isSyncing = false

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isSyncing else { return }
            guard let textView = notification.object as? NSTextView else { return }
            viewModel.updateText(textView.string)
        }

        // MARK: - EditorTextView callbacks

        func handleSubmit(_ text: String) {
            viewModel.submit()
        }

        func handleNewline() {
            viewModel.insertNewline()
        }

        func handleHistory(previous: Bool) {
            if previous {
                viewModel.navigatePrevious()
            } else {
                viewModel.navigateNext()
            }
        }

        /// Forward raw PTY control sequences (Ctrl+C, Escape, etc.) without appending \n.
        func handleControlSequence(_ seq: String) {
            viewModel.sendRaw(seq)
        }
    }
}
