import AppKit
import Highlightr
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "CodeEditorView")

// MARK: - File-backed editor (for project files and harness rules)

/// Editable code viewer with line numbers and Markdown syntax dimming.
/// Loads content from a file path on disk.
struct CodeEditorView: View {
    let filePath: String
    let projectRoot: String
    @EnvironmentObject var fontSettings: FontSettings

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

    /// Map file extension to highlight.js language identifier.
    private var highlightLanguage: String? {
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        return Self.extensionToLanguage[ext]
    }

    private static let extensionToLanguage: [String: String] = [
        "swift": "swift", "m": "objectivec", "h": "objectivec",
        "c": "c", "cpp": "cpp", "cc": "cpp", "cxx": "cpp",
        "rs": "rust", "go": "go", "py": "python", "rb": "ruby",
        "js": "javascript", "ts": "typescript", "jsx": "javascript", "tsx": "typescript",
        "json": "json", "yaml": "yaml", "yml": "yaml", "toml": "ini",
        "xml": "xml", "plist": "xml", "html": "xml",
        "css": "css", "scss": "scss", "less": "less",
        "sh": "bash", "bash": "bash", "zsh": "bash", "fish": "fish",
        "sql": "sql", "graphql": "graphql",
        "java": "java", "kt": "kotlin", "scala": "scala",
        "dart": "dart", "php": "php", "lua": "lua",
        "r": "r", "zig": "zig", "nim": "nim",
        "ex": "elixir", "exs": "elixir",
        "vue": "xml", "svelte": "xml",
        "md": "markdown", "markdown": "markdown",
    ]

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
                    onSave: saveFile,
                    fontFamily: fontSettings.terminalFontFamily,
                    fontSize: fontSettings.editorFontSize,
                    language: highlightLanguage
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
    @EnvironmentObject var fontSettings: FontSettings

    @State private var isModified = false

    var body: some View {
        VStack(spacing: 0) {
            editorHeader(title: title, isModified: false, onSave: nil)
            Divider()
            CodeEditorTextViewRepresentable(
                text: $text,
                isModified: $isModified,
                onSave: {},
                fontFamily: fontSettings.terminalFontFamily,
                fontSize: fontSettings.editorFontSize
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
                .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
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
    let fontFamily: String
    let fontSize: CGFloat
    /// highlight.js language identifier (e.g. "swift", "python"). Nil = plain text.
    var language: String?

    /// Extra spacing between lines (points). Uses lineSpacing instead of
    /// lineHeightMultiple so the cursor height matches the font, not the full line.
    static let lineSpacingExtra: CGFloat = 6
    /// Horizontal inset inside the text container.
    static let textInsetWidth: CGFloat = 8
    /// Vertical inset inside the text container.
    static let textInsetHeight: CGFloat = 8

    /// Shared Highlightr instance (heavy to create, reuse across views).
    private static let sharedHighlightr: Highlightr? = {
        let h = Highlightr()
        h?.setTheme(to: "atom-one-dark")
        // Make theme background transparent — we use the text view's own background.
        h?.theme.themeBackgroundColor = .clear
        return h
    }()

    private func resolvedFont() -> NSFont {
        NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true

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
        textView.textContainerInset = NSSize(
            width: Self.textInsetWidth,
            height: Self.textInsetHeight
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Self.lineSpacingExtra
        textView.defaultParagraphStyle = paragraphStyle
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.onSave = onSave

        // Set text and apply highlighting BEFORE setting delegate.
        // This prevents textDidChange from firing during view creation,
        // which would mutate SwiftUI state during a view update (illegal).
        textView.string = text
        context.coordinator.isHighlighting = true
        applySyntaxHighlighting(to: textView)
        context.coordinator.isHighlighting = false
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        // Line number ruler
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(
            textView: textView,
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineSpacing: Self.lineSpacingExtra
        )
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            // Temporarily remove delegate to prevent textDidChange during programmatic update
            textView.delegate = nil
            textView.string = text
            applySyntaxHighlighting(to: textView)
            textView.delegate = context.coordinator
        }
        textView.isEditable = true

        // Sync font when settings change
        let newFont = resolvedFont()
        if textView.font != newFont {
            textView.font = newFont
            textView.defaultParagraphStyle = {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = Self.lineSpacingExtra
                return p
            }()
            textView.delegate = nil
            applySyntaxHighlighting(to: textView)
            textView.delegate = context.coordinator
        }

        // Sync ruler font
        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.updateFont(family: fontFamily, size: fontSize)
        }
    }

    // MARK: - Syntax Highlighting

    private func applySyntaxHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let text = textStorage.string
        guard !text.isEmpty else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseFont = resolvedFont()
        let baseColor = NSColor.textColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Self.lineSpacingExtra

        textStorage.beginEditing()

        // 1. Apply baseline attributes (addAttributes preserves NSTextView internal attrs;
        //    setAttributes strips them and causes invisible text)
        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: paragraphStyle
        ], range: fullRange)

        // 2. Apply syntax colors from Highlightr (if available)
        if let highlightr = Self.sharedHighlightr, let lang = language {
            highlightr.theme.setCodeFont(baseFont)
            if let highlighted = highlightr.highlight(text, as: lang),
               highlighted.length == textStorage.length {
                // Copy only foreground colors from Highlightr — our baseline handles font/spacing
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
            // No Highlightr or no language — use Markdown dimmer colors
            MarkdownSyntaxDimmer.applyColors(to: textStorage, range: fullRange)
        }

        textStorage.endEditing()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeEditorTextViewRepresentable
        /// Prevents infinite loop: applySyntaxHighlighting modifies textStorage,
        /// which fires textDidChange, which would call applySyntaxHighlighting again.
        var isHighlighting = false

        init(_ parent: CodeEditorTextViewRepresentable) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting,
                  let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            // Only react to actual content changes, not attribute-only changes
            guard newText != parent.text else { return }
            parent.text = newText
            parent.isModified = true
            isHighlighting = true
            parent.applySyntaxHighlighting(to: textView)
            isHighlighting = false
        }
    }
}
