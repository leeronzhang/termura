import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "CodeEditorView")

// MARK: - File-backed editor (for project files and harness rules)

/// Editable code viewer with line numbers and Markdown syntax dimming.
/// Loads content from a file path on disk.
struct CodeEditorView: View {
    let filePath: String
    let projectRoot: String

    @State private var content = ""
    @State private var isLoading = true
    @State private var isModified = false
    @State private var errorMessage: String?

    private var absolutePath: String {
        if filePath.hasPrefix("/") { return filePath }
        return URL(fileURLWithPath: projectRoot).appendingPathComponent(filePath).path
    }

    private var displayPath: String {
        if filePath.hasPrefix("/") {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        return filePath
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader(title: displayPath, isModified: isModified, onSave: saveFile)
            Divider()
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                editorErrorView(error)
            } else {
                CodeEditorTextViewRepresentable(
                    text: $content,
                    isModified: $isModified,
                    onSave: saveFile
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadFile() }
    }

    private func loadFile() async {
        let path = absolutePath
        let result: Result<String, Error> = await Task.detached {
            Result { try String(contentsOfFile: path, encoding: .utf8) }
        }.value
        switch result {
        case .success(let text):
            content = text
        case .failure(let error):
            logger.warning("Failed to read \(path): \(error.localizedDescription)")
            errorMessage = "Cannot read file"
        }
        isLoading = false
    }

    private func saveFile() {
        let path = absolutePath
        let text = content
        Task.detached {
            do {
                try text.write(toFile: path, atomically: true, encoding: .utf8)
                await MainActor.run { isModified = false }
                logger.info("Saved \(path)")
            } catch {
                logger.warning("Failed to save \(path): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Binding-backed editor (for notes stored in GRDB)

/// Editable code viewer backed by a text Binding (no file I/O).
/// Used for notes whose content lives in the database.
struct NoteEditorView: View {
    let title: String
    @Binding var text: String

    @State private var isModified = false

    var body: some View {
        VStack(spacing: 0) {
            editorHeader(title: title, isModified: false, onSave: nil)
            Divider()
            CodeEditorTextViewRepresentable(
                text: $text,
                isModified: $isModified,
                onSave: {}
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared header & error

@MainActor
private func editorHeader(title: String, isModified: Bool, onSave: (() -> Void)?) -> some View {
    HStack(spacing: AppUI.Spacing.md) {
        Image(systemName: "doc.text")
            .font(AppUI.Font.label)
            .foregroundColor(.secondary)
        Text(title)
            .font(AppUI.Font.labelMono)
            .lineLimit(1)
            .truncationMode(.head)
        if isModified {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
        }
        Spacer()
        if isModified, let onSave {
            Button("Save") { onSave() }
                .font(AppUI.Font.label)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
        }
    }
    .padding(.horizontal, AppUI.Spacing.xxxl)
    .padding(.vertical, AppUI.Spacing.mdLg)
}

private func editorErrorView(_ message: String) -> some View {
    VStack(spacing: AppUI.Spacing.md) {
        Image(systemName: "exclamationmark.triangle")
            .font(AppUI.Font.hero)
            .foregroundColor(.secondary)
        Text(message)
            .font(AppUI.Font.label)
            .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

// MARK: - NSViewRepresentable

struct CodeEditorTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var isModified: Bool
    let onSave: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

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
        textView.font = NSFont(name: AppConfig.Fonts.terminalFamily, size: AppConfig.Fonts.editorSize)
            ?? NSFont.monospacedSystemFont(ofSize: AppConfig.Fonts.editorSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.delegate = context.coordinator
        textView.onSave = onSave
        textView.string = text
        MarkdownSyntaxDimmer.apply(to: textView)

        scrollView.documentView = textView

        // Line number ruler
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            MarkdownSyntaxDimmer.apply(to: textView)
        }
        textView.isEditable = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeEditorTextViewRepresentable
        init(_ parent: CodeEditorTextViewRepresentable) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.isModified = true
            MarkdownSyntaxDimmer.apply(to: textView)
        }
    }
}

// MARK: - Markdown Syntax Dimmer

/// Applies lightweight syntax dimming to Markdown content:
/// syntax characters (#, *, -, `, >, etc.) are rendered in a muted color
/// while the actual content text stays at normal color.
@MainActor
enum MarkdownSyntaxDimmer {
    static func apply(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let text = textStorage.string
        guard !text.isEmpty else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let normalFont = textView.font ?? NSFont.monospacedSystemFont(
            ofSize: AppConfig.Fonts.editorSize, weight: .regular
        )
        let normalColor = NSColor.textColor
        let dimColor = NSColor.tertiaryLabelColor

        // Reset to normal
        textStorage.beginEditing()
        textStorage.addAttributes([
            .foregroundColor: normalColor,
            .font: normalFont
        ], range: fullRange)

        let nsText = text as NSString
        let lineCount = nsText.length
        var lineStart = 0

        while lineStart < lineCount {
            let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = nsText.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Heading: dim the leading ### characters
            if trimmed.hasPrefix("#") {
                if let hashEnd = trimmed.firstIndex(where: { $0 != "#" && $0 != " " }) {
                    let prefixCount = trimmed.distance(from: trimmed.startIndex, to: hashEnd)
                    let leadingSpaces = line.count - line.drop(while: { $0 == " " }).count
                    let dimRange = NSRange(location: lineRange.location + leadingSpaces, length: prefixCount)
                    if dimRange.location + dimRange.length <= textStorage.length {
                        textStorage.addAttribute(.foregroundColor, value: dimColor, range: dimRange)
                    }
                }
            }

            // Block quote: dim leading >
            if trimmed.hasPrefix(">") {
                let leadingSpaces = line.count - line.drop(while: { $0 == " " }).count
                var prefixLen = 1
                if trimmed.count > 1 && trimmed[trimmed.index(after: trimmed.startIndex)] == " " {
                    prefixLen = 2
                }
                let dimRange = NSRange(location: lineRange.location + leadingSpaces, length: prefixLen)
                if dimRange.location + dimRange.length <= textStorage.length {
                    textStorage.addAttribute(.foregroundColor, value: dimColor, range: dimRange)
                }
            }

            // List markers: dim leading -, *, +
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let leadingSpaces = line.count - line.drop(while: { $0 == " " }).count
                let dimRange = NSRange(location: lineRange.location + leadingSpaces, length: 2)
                if dimRange.location + dimRange.length <= textStorage.length {
                    textStorage.addAttribute(.foregroundColor, value: dimColor, range: dimRange)
                }
            }

            // Horizontal rule: dim entire line (---, ***, ___)
            if trimmed.count >= 3 {
                let chars = Set(trimmed)
                if (chars == ["-"] || chars == ["*"] || chars == ["_"] || chars == ["-", " "] || chars == ["*", " "]) {
                    textStorage.addAttribute(.foregroundColor, value: dimColor, range: lineRange)
                }
            }

            lineStart = NSMaxRange(lineRange)
        }

        // Inline code: dim backticks
        dimPattern("`[^`]+`", in: textStorage, dimColor: dimColor, dimChars: 1)
        // Bold: dim **
        dimPattern("\\*\\*[^*]+\\*\\*", in: textStorage, dimColor: dimColor, dimChars: 2)
        // Italic: dim single *
        dimPattern("(?<!\\*)\\*[^*]+\\*(?!\\*)", in: textStorage, dimColor: dimColor, dimChars: 1)
        // Fenced code block markers: dim entire ``` line
        dimPattern("^```.*$", in: textStorage, dimColor: dimColor, dimChars: nil, options: [.anchorsMatchLines])

        textStorage.endEditing()
    }

    /// Dims the first/last N characters of each regex match, or the entire match if `dimChars` is nil.
    private static func dimPattern(
        _ pattern: String,
        in storage: NSTextStorage,
        dimColor: NSColor,
        dimChars: Int?,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        regex.enumerateMatches(in: storage.string, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            if let n = dimChars {
                // Dim only the syntax markers (first N and last N chars)
                if range.length > n * 2 {
                    let startRange = NSRange(location: range.location, length: n)
                    let endRange = NSRange(location: range.location + range.length - n, length: n)
                    storage.addAttribute(.foregroundColor, value: dimColor, range: startRange)
                    storage.addAttribute(.foregroundColor, value: dimColor, range: endRange)
                }
            } else {
                storage.addAttribute(.foregroundColor, value: dimColor, range: range)
            }
        }
    }
}

// MARK: - Cmd+S support

private final class SaveableTextView: NSTextView {
    var onSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Line Number Ruler

private final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
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
    required init(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    @objc private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let text = textView.string as NSString
        let visibleRect = textView.visibleRect
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let prefix = text.substring(to: min(charRange.location, text.length))
        var lineNumber = 1
        var searchRange = NSRange(location: 0, length: prefix.count)
        let ns = prefix as NSString
        while searchRange.length > 0 {
            let found = ns.range(of: "\n", options: [], range: searchRange)
            if found.location == NSNotFound { break }
            lineNumber += 1
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: ns.length - next)
        }

        var index = charRange.location
        while index < NSMaxRange(charRange) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyphIdx = layoutManager.glyphIndexForCharacter(at: index)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            let yInRuler = convert(NSPoint(x: 0, y: lineRect.origin.y), from: textView).y

            let numStr = "\(lineNumber)" as NSString
            let strSize = numStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: ruleThickness - strSize.width - 6,
                y: yInRuler + (lineRect.height - strSize.height) / 2
            )
            numStr.draw(at: drawPoint, withAttributes: attrs)

            lineNumber += 1
            index = NSMaxRange(lineRange)
        }
    }
}
