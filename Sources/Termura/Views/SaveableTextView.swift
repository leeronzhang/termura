import AppKit

// MARK: - Cmd+S support and indent guides

final class SaveableTextView: NSTextView {
    var onSave: (() -> Void)?
    /// Number of spaces per indent level for drawing indent guides.
    var indentWidth: Int = 4

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "s":
            onSave?()
            return true
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard let resolvedFont = font else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }
        let fontHeight = resolvedFont.ascender - resolvedFont.descender
        var adjusted = rect
        adjusted.size.height = fontHeight
        super.drawInsertionPoint(in: adjusted, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var expanded = rect
        expanded.size.height += 4
        expanded = expanded.intersection(bounds)
        super.setNeedsDisplay(expanded, avoidAdditionalLayout: flag)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        NSGraphicsContext.saveGraphicsState()
        bounds.intersection(rect).clip()
        drawIndentGuides(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private struct IndentSegment { var minY: CGFloat; var maxY: CGFloat }

    /// Draws vertical indent guide lines at each indentation level.
    private func drawIndentGuides(in rect: NSRect) {
        guard let layoutManager, let textContainer,
              let resolvedFont = font else { return }
        let spaceWidth = NSString(" ").size(withAttributes: [.font: resolvedFont]).width
        let tabWidth = spaceWidth * CGFloat(indentWidth)
        guard tabWidth > 1 else { return }

        let origin = textContainerOrigin
        let xBase = origin.x + textContainerInset.width

        NSColor.separatorColor.withAlphaComponent(0.15).setStroke()

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: rect, in: textContainer
        )
        guard visibleGlyphRange.length > 0 else { return }
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange, actualGlyphRange: nil
        )

        let levelSegments = collectIndentSegments(
            charRange: visibleCharRange, origin: origin, layoutManager: layoutManager
        )
        guard !levelSegments.isEmpty else { return }
        strokeIndentGuides(levelSegments, xBase: xBase, tabWidth: tabWidth)
    }

    private func collectIndentSegments(
        charRange: NSRange, origin: NSPoint, layoutManager: NSLayoutManager
    ) -> [Int: [IndentSegment]] {
        let text = string as NSString
        var levelSegments: [Int: [IndentSegment]] = [:]
        var maxLineHeight: CGFloat = 20
        var idx = charRange.location

        while idx < NSMaxRange(charRange) {
            let lineRange = text.lineRange(for: NSRange(location: idx, length: 0))
            let lineStr = text.substring(with: lineRange)
            let trimmed = lineStr.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                idx = NSMaxRange(lineRange)
                continue
            }

            let spaces = lineStr.prefix(while: { $0 == " " || $0 == "\t" })
                .reduce(0) { $0 + ($1 == "\t" ? indentWidth : 1) }
            let level = spaces / indentWidth
            if level > 0 {
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: lineRange, actualCharacterRange: nil
                )
                if glyphRange.length > 0 {
                    let lineRect = layoutManager.lineFragmentRect(
                        forGlyphAt: glyphRange.location, effectiveRange: nil
                    )
                    maxLineHeight = max(maxLineHeight, lineRect.height)
                    let top = lineRect.origin.y + origin.y
                    let bottom = lineRect.maxY + origin.y
                    for lv in 0..<level {
                        var segs = levelSegments[lv, default: []]
                        if var last = segs.last, (top - last.maxY) < maxLineHeight * 2 {
                            last.maxY = bottom
                            segs[segs.count - 1] = last
                        } else {
                            segs.append(IndentSegment(minY: top, maxY: bottom))
                        }
                        levelSegments[lv] = segs
                    }
                }
            }
            idx = NSMaxRange(lineRange)
        }
        return levelSegments
    }

    private func strokeIndentGuides(
        _ levelSegments: [Int: [IndentSegment]], xBase: CGFloat, tabWidth: CGFloat
    ) {
        let path = NSBezierPath()
        path.lineWidth = 1.0
        for (level, segments) in levelSegments {
            let xPos = (xBase + CGFloat(level) * tabWidth).rounded(.down) + 0.5
            for seg in segments {
                path.move(to: NSPoint(x: xPos, y: seg.minY))
                path.line(to: NSPoint(x: xPos, y: seg.maxY))
            }
        }
        path.stroke()
    }
}
