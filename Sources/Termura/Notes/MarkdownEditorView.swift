import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        let markdownView = MarkdownTextView(
            frame: textView.frame,
            textContainer: textView.textContainer
        )
        scrollView.documentView = markdownView
        markdownView.delegate = context.coordinator
        markdownView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        if textView.string != text {
            context.coordinator.isUpdating = true
            textView.string = text
            textView.applyHighlighting(to: text)
            context.coordinator.isUpdating = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isUpdating = false

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? MarkdownTextView else { return }
            text.wrappedValue = textView.string
            textView.applyHighlighting(to: textView.string)
        }
    }
}
