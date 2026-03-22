import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        let textContainer = NSTextContainer(size: containerSize)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let markdownView = MarkdownTextView(
            frame: NSRect(origin: .zero, size: scrollView.contentSize),
            textContainer: textContainer
        )
        markdownView.isVerticallyResizable = true
        markdownView.isHorizontallyResizable = false
        markdownView.autoresizingMask = [.width]
        markdownView.delegate = context.coordinator
        markdownView.string = text

        scrollView.documentView = markdownView
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
