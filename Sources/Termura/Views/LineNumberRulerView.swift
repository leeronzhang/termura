import AppKit
import OSLog

private let rulerLogger = Logger(subsystem: "com.termura.app", category: "LineNumberRulerView")

// MARK: - Line Number Ruler

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var fontFamily: String
    private var fontSize: CGFloat
    private var lineHeightMultiple: CGFloat

    /// Right-side padding between line number text and the ruler edge.
    private static let trailingPadding: CGFloat = 6

    init(
        textView: NSTextView,
        fontFamily: String,
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat
    ) {
        self.textView = textView
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = 40
        clientView = textView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    /// Called from `updateNSView` when font settings change.
    func updateFont(family: String, size: CGFloat) {
        guard family != fontFamily || size != fontSize else { return }
        fontFamily = family
        fontSize = size
        needsDisplay = true
    }

    @objc private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    private func rulerAttributes() -> [NSAttributedString.Key: Any] {
        let rulerFontSize = max(fontSize - 3, FontSettings.minSize)
        let rulerFont = NSFont(name: fontFamily, size: rulerFontSize)
            ?? NSFont.monospacedDigitSystemFont(ofSize: rulerFontSize, weight: .regular)
        return [
            .font: rulerFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let text = textView.string as NSString
        guard text.length > 0 else { return }

        layoutManager.ensureLayout(for: textContainer)

        let ctx = DrawingContext(
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            attrs: rulerAttributes(),
            containerOrigin: textView.textContainerOrigin
        )

        let margin = fontSize * lineHeightMultiple * 2
        let visibleRange = computeVisibleRange(text: text, context: ctx, margin: margin)
        drawLineNumbers(text: text, visibleRange: visibleRange, context: ctx)
    }
}

// MARK: - Drawing helpers

@MainActor
private extension LineNumberRulerView {

    struct DrawingContext {
        let textView: NSTextView
        let layoutManager: NSLayoutManager
        let textContainer: NSTextContainer
        let attrs: [NSAttributedString.Key: Any]
        let containerOrigin: NSPoint
    }

    func computeVisibleRange(text: NSString, context: DrawingContext, margin: CGFloat) -> NSRange {
        let visibleRect = context.textView.visibleRect
        let topY = max(visibleRect.origin.y - context.containerOrigin.y - margin, 0)
        let bottomY = visibleRect.maxY - context.containerOrigin.y + margin

        let topCharIdx = context.layoutManager.characterIndex(
            for: NSPoint(x: 0, y: topY),
            in: context.textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        let bottomCharIdx = context.layoutManager.characterIndex(
            for: NSPoint(x: 0, y: bottomY),
            in: context.textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        let startLine = text.lineRange(for: NSRange(location: topCharIdx, length: 0))
        let endLine = text.lineRange(for: NSRange(
            location: min(bottomCharIdx, text.length - 1), length: 0
        ))
        return NSRange(location: startLine.location, length: NSMaxRange(endLine) - startLine.location)
    }

    func drawLineNumbers(text: NSString, visibleRange: NSRange, context: DrawingContext) {
        var lineNumber = countNewlines(in: text, upTo: visibleRange.location)
        var index = visibleRange.location

        while index < NSMaxRange(visibleRange) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = context.layoutManager.glyphRange(
                forCharacterRange: lineRange, actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else {
                lineNumber += 1
                index = NSMaxRange(lineRange)
                continue
            }

            drawSingleNumber(lineNumber, glyphIndex: glyphRange.location, context: context)

            lineNumber += 1
            index = NSMaxRange(lineRange)
        }
    }

    func countNewlines(in text: NSString, upTo location: Int) -> Int {
        var count = 1
        guard location > 0 else { return count }
        let prefix = text.substring(to: location) as NSString
        var sr = NSRange(location: 0, length: prefix.length)
        while sr.length > 0 {
            let found = prefix.range(of: "\n", options: [], range: sr)
            if found.location == NSNotFound { break }
            count += 1
            let next = found.location + found.length
            sr = NSRange(location: next, length: prefix.length - next)
        }
        return count
    }

    func drawSingleNumber(_ lineNumber: Int, glyphIndex: Int, context: DrawingContext) {
        let lineRect = context.layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex, effectiveRange: nil
        )
        let baseline = context.layoutManager.location(forGlyphAt: glyphIndex)

        let yInTextView = lineRect.origin.y + context.containerOrigin.y
        let yInRuler = convert(NSPoint(x: 0, y: yInTextView), from: context.textView).y

        let numStr = "\(lineNumber)" as NSString
        let strSize = numStr.size(withAttributes: context.attrs)
        let rulerFont = context.attrs[.font] as? NSFont
        let ascender = rulerFont?.ascender ?? strSize.height
        let baselineInRuler = yInRuler + baseline.y
        let drawPoint = NSPoint(
            x: ruleThickness - strSize.width - Self.trailingPadding,
            y: baselineInRuler - ascender
        )
        numStr.draw(at: drawPoint, withAttributes: context.attrs)
    }
}
