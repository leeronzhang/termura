import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "MarkdownFileView")

/// Editable markdown viewer for project files (docs/*.md, README.md, etc.).
/// Provides the same edit / reading toggle as `NoteTabContentView` but operates
/// on a file path rather than a NoteID — no dependency on the Notes subsystem.
struct MarkdownFileView: View {
    let filePath: String
    let projectRoot: String

    @Environment(\.fontSettings) var fontSettings
    @Environment(\.themeManager) var themeManager
    @Environment(\.webViewPool) var webViewPool
    @Environment(\.webRendererBridge) var webRendererBridge
    @Environment(\.commandRouter) private var commandRouter

    @State var content = ""
    @State var isLoading = true
    @State var isModified = false
    @State var errorMessage: String?
    @State private var viewMode: NoteViewMode = .reading
    @State private var isHoveringPath = false

    var absolutePath: String {
        if filePath.hasPrefix("/") { return filePath }
        return URL(fileURLWithPath: projectRoot).appendingPathComponent(filePath).standardized.path
    }

    private var projectURL: URL { URL(fileURLWithPath: projectRoot) }

    private var breadcrumbComponents: [String] {
        let raw = filePath.hasPrefix("/")
            ? MetadataFormatter.abbreviateDirectory(filePath)
            : filePath
        return raw.split(separator: "/").map(String.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                contentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadFile() }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .edit:
            CodeEditorTextViewRepresentable(
                text: $content,
                isModified: $isModified,
                onSave: saveFile,
                fontFamily: fontSettings.terminalFontFamily,
                fontSize: fontSettings.editorFontSize,
                language: "markdown"
            )
        case .reading:
            NoteRenderedView(
                pool: webViewPool,
                bridge: webRendererBridge,
                theme: themeManager.current,
                markdown: content,
                references: [],
                backlinks: [],
                projectURL: projectURL
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            breadcrumbs
            copyPathButton
                .padding(.leading, AppUI.Spacing.md)
            if isModified {
                Circle()
                    .fill(Color.orange)
                    .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                    .padding(.leading, AppUI.Spacing.sm)
            }
            Spacer()
            if isModified {
                Button("Save") { saveFile() }
                    .font(AppUI.Font.label)
                    .buttonStyle(.plain)
                    .foregroundColor(.brandGreen)
                Spacer().frame(width: AppUI.Spacing.xxl)
            }
            modeToggle
            Spacer().frame(width: AppUI.Spacing.xxl)
            finderButton
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringPath = hovering
            }
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            ForEach(Array(breadcrumbComponents.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(AppUI.Font.chevron)
                        .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
                }
                Text(part)
                    .font(AppUI.Font.pathMono)
                    .foregroundColor(
                        index == breadcrumbComponents.count - 1
                            ? .secondary.opacity(AppUI.Opacity.strong)
                            : .secondary.opacity(AppUI.Opacity.dimmed)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    /// Hover-revealed shortcut: one click copies `<filename>\n<absolute path>`
    /// to the system pasteboard. Mirrors the affordance in CodeEditorView so
    /// markdown previews behave the same way.
    private var copyPathButton: some View {
        Button(action: copyNameAndPath) {
            HStack(spacing: AppUI.Spacing.xs) {
                Image(systemName: "doc.on.doc")
                Text("Copy name & path")
            }
            .font(AppUI.Font.label)
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .opacity(isHoveringPath ? 1 : 0)
        .allowsHitTesting(isHoveringPath)
        .help("Copy filename and absolute path to clipboard")
    }

    private func copyNameAndPath() {
        let path = absolutePath
        let fileName = (path as NSString).lastPathComponent
        let payload = "\(fileName)\n\(path)"
        // §3.2 exception: NSPasteboard is a platform bridge invoked from
        // the view layer (matches existing usages in CodeEditorView /
        // EditorTextView). Future PasteboardService extraction is tracked
        // separately.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(payload, forType: .string)
        commandRouter.showToast(didWrite ? "Copied filename and path" : "Copy failed")
    }

    private var modeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewMode = viewMode == .edit ? .reading : .edit
            }
        } label: {
            Image(systemName: viewMode == .edit ? "eye" : "highlighter")
                .font(AppUI.Font.body)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(viewMode == .edit ? "Switch to Reading mode" : "Switch to Edit mode")
        .accessibilityLabel(viewMode == .edit ? "Switch to Reading mode" : "Switch to Edit mode")
    }

    private var finderButton: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: absolutePath)]
            )
        } label: {
            Image(systemName: "folder")
                .font(AppUI.Font.body)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
        .accessibilityLabel("Show in Finder")
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
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
}
