import AppKit
import Highlightr
import SwiftUI

// MARK: - NSViewRepresentable

struct CodeEditorTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var isModified: Bool
    let onSave: () -> Void
    let fontFamily: String
    let fontSize: CGFloat
    /// highlight.js language identifier (e.g. "swift", "python"). Nil = plain text.
    var language: String?

    /// Extra spacing between lines (points). Uses lineSpacing instead of
    /// lineHeightMultiple so the cursor height matches the font, not the full line.
    static let lineSpacingExtra: CGFloat = AppConfig.UI.codeEditorLineSpacing
    /// Horizontal inset inside the text container.
    static let textInsetWidth: CGFloat = AppConfig.UI.codeEditorTextInset
    /// Vertical inset inside the text container.
    static let textInsetHeight: CGFloat = AppConfig.UI.codeEditorTextInset

    /// Shared Highlightr instance (heavy to create, reuse across views).
    private static let sharedHighlightr: Highlightr? = {
        let highlightr = Highlightr()
        highlightr?.setTheme(to: "atom-one-dark")
        highlightr?.theme.themeBackgroundColor = .clear
        return highlightr
    }()

    private func resolvedFont() -> NSFont {
        NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = makeScrollView()
        let textView = makeTextView(coordinator: context.coordinator)
        scrollView.documentView = textView
        attachRuler(to: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        syncText(textView, coordinator: context.coordinator)
        syncFont(textView, coordinator: context.coordinator)
        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.updateFont(family: fontFamily, size: fontSize)
        }
    }

    // MARK: - View Construction Helpers

    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true
        return scrollView
    }

    private func makeTextView(coordinator: Coordinator) -> SaveableTextView {
        let textView = SaveableTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = resolvedFont()
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: Self.textInsetWidth, height: Self.textInsetHeight)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Self.lineSpacingExtra
        textView.defaultParagraphStyle = paragraphStyle
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.onSave = onSave
        textView.string = text
        coordinator.isHighlighting = true
        applySyntaxHighlighting(to: textView)
        coordinator.isHighlighting = false
        textView.delegate = coordinator
        return textView
    }

    private func attachRuler(to scrollView: NSScrollView, textView: SaveableTextView) {
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(
            textView: textView,
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineSpacing: Self.lineSpacingExtra
        )
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
    }

    // MARK: - Sync Helpers

    private func syncText(_ textView: NSTextView, coordinator: Coordinator) {
        guard textView.string != text else { return }
        textView.delegate = nil
        textView.string = text
        applySyntaxHighlighting(to: textView)
        textView.delegate = coordinator
    }

    private func syncFont(_ textView: NSTextView, coordinator: Coordinator) {
        let newFont = resolvedFont()
        guard textView.font != newFont else { return }
        textView.font = newFont
        textView.defaultParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = Self.lineSpacingExtra
            return style
        }()
        textView.delegate = nil
        applySyntaxHighlighting(to: textView)
        textView.delegate = coordinator
    }

    // MARK: - Syntax Highlighting

    private func applySyntaxHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let content = textStorage.string
        guard !content.isEmpty else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseFont = resolvedFont()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Self.lineSpacingExtra

        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ], range: fullRange)

        if let highlightr = Self.sharedHighlightr, let lang = language {
            highlightr.theme.setCodeFont(baseFont)
            if let highlighted = highlightr.highlight(content, as: lang),
               highlighted.length == textStorage.length {
                let hlRange = NSRange(location: 0, length: highlighted.length)
                highlighted.enumerateAttribute(
                    .foregroundColor, in: hlRange, options: []
                ) { value, range, _ in
                    if let color = value as? NSColor {
                        textStorage.addAttribute(.foregroundColor, value: color, range: range)
                    }
                }
            }
        } else {
            MarkdownSyntaxDimmer.applyColors(to: textStorage, range: fullRange)
        }
        textStorage.endEditing()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeEditorTextViewRepresentable
        var isHighlighting = false

        init(_ parent: CodeEditorTextViewRepresentable) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting,
                  let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            guard newText != parent.text else { return }
            parent.text = newText
            parent.isModified = true
            isHighlighting = true
            parent.applySyntaxHighlighting(to: textView)
            isHighlighting = false
        }
    }
}
