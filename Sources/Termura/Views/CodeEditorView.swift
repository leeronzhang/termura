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
                    fontSize: fontSettings.editorFontSize
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
    let fontFamily: String
    let fontSize: CGFloat

    /// Line height multiplier shared between text view and ruler.
    static let lineHeightMultiple: CGFloat = 1.4
    /// Horizontal inset inside the text container.
    static let textInsetWidth: CGFloat = 8
    /// Vertical inset inside the text container.
    static let textInsetHeight: CGFloat = 8

    private func resolvedFont() -> NSFont {
        NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

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
        textView.font = resolvedFont()
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(
            width: Self.textInsetWidth,
            height: Self.textInsetHeight
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = Self.lineHeightMultiple
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
        textView.delegate = context.coordinator
        textView.onSave = onSave
        textView.string = text
        MarkdownSyntaxDimmer.apply(to: textView)

        scrollView.documentView = textView

        // Line number ruler
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(
            textView: textView,
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineHeightMultiple: Self.lineHeightMultiple
        )
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

        // Sync font when settings change
        let newFont = resolvedFont()
        if textView.font != newFont {
            textView.font = newFont
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = Self.lineHeightMultiple
            textView.defaultParagraphStyle = paragraphStyle
            // Re-apply paragraph style to existing text
            if let textStorage = textView.textStorage, textStorage.length > 0 {
                let fullRange = NSRange(location: 0, length: textStorage.length)
                textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
                textStorage.addAttribute(.font, value: newFont, range: fullRange)
            }
            MarkdownSyntaxDimmer.apply(to: textView)
        }

        // Sync ruler font
        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.updateFont(family: fontFamily, size: fontSize)
        }
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
