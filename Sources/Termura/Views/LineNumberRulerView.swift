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

    /// Build ruler number attributes that match the editor font.
    /// Uses the same font family at a slightly smaller size so line numbers
    /// stay visually subordinate while sharing the same baseline metrics.
    /// NOTE: No paragraphStyle here — adding lineHeightMultiple inflates
    /// `size(withAttributes:).height`, which breaks the baseline calculation.
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
        let containerOrigin = textView.textContainerOrigin
        let attrs = rulerAttributes()

        layoutManager.ensureLayout(for: textContainer)

        let visibleRect = textView.visibleRect
        let margin = fontSize * lineHeightMultiple * 2

        drawVisibleLineNumbers(
            text: text,
            visibleRect: visibleRect,
            containerOrigin: containerOrigin,
            margin: margin,
            layoutManager: layoutManager,
            textContainer: textContainer,
            attrs: attrs
        )
    }

    private func drawVisibleLineNumbers(
        text: NSString,
        visibleRect: NSRect,
        containerOrigin: NSPoint,
        margin: CGFloat,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        attrs: [NSAttributedString.Key: Any]
    ) {
        let topY = max(visibleRect.origin.y - containerOrigin.y - margin, 0)
        let bottomY = visibleRect.maxY - containerOrigin.y + margin

        let topCharIdx = layoutManager.characterIndex(
            for: NSPoint(x: 0, y: topY),
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        let bottomCharIdx = layoutManager.characterIndex(
            for: NSPoint(x: 0, y: bottomY),
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        let startLine = text.lineRange(for: NSRange(location: topCharIdx, length: 0))
        let endLine = text.lineRange(for: NSRange(
            location: min(bottomCharIdx, text.length - 1), length: 0
        ))
        let visibleCharRange = NSRange(
            location: startLine.location,
            length: NSMaxRange(endLine) - startLine.location
        )

        var lineNumber = countPrecedingNewlines(text: text, upTo: visibleCharRange.location)
        var index = visibleCharRange.location

        while index < NSMaxRange(visibleCharRange) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange, actualCharacterRange: nil
            )
            guard lineGlyphRange.length > 0 else {
                lineNumber += 1
                index = NSMaxRange(lineRange)
                continue
            }

            drawLineNumber(
                lineNumber,
                glyphIndex: lineGlyphRange.location,
                layoutManager: layoutManager,
                containerOrigin: containerOrigin,
                attrs: attrs
            )

            lineNumber += 1
            index = NSMaxRange(lineRange)
        }
    }

    private func countPrecedingNewlines(text: NSString, upTo location: Int) -> Int {
        var lineNumber = 1
        guard location > 0 else { return lineNumber }
        let prefix = text.substring(to: location) as NSString
        var sr = NSRange(location: 0, length: prefix.length)
        while sr.length > 0 {
            let found = prefix.range(of: "\n", options: [], range: sr)
            if found.location == NSNotFound { break }
            lineNumber += 1
            let next = found.location + found.length
            sr = NSRange(location: next, length: prefix.length - next)
        }
        return lineNumber
    }

    private func drawLineNumber(
        _ lineNumber: Int,
        glyphIndex: Int,
        layoutManager: NSLayoutManager,
        containerOrigin: NSPoint,
        attrs: [NSAttributedString.Key: Any]
    ) {
        guard let textView else { return }
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex, effectiveRange: nil
        )
        let baseline = layoutManager.location(forGlyphAt: glyphIndex)

        let yInTextView = lineRect.origin.y + containerOrigin.y
        let yInRuler = convert(NSPoint(x: 0, y: yInTextView), from: textView).y

        let numStr = "\(lineNumber)" as NSString
        let strSize = numStr.size(withAttributes: attrs)
        let rulerFont = attrs[.font] as? NSFont
        let ascender = rulerFont?.ascender ?? strSize.height
        let baselineInRuler = yInRuler + baseline.y
        let drawPoint = NSPoint(
            x: ruleThickness - strSize.width - Self.trailingPadding,
            y: baselineInRuler - ascender
        )
        numStr.draw(at: drawPoint, withAttributes: attrs)
    }
}
