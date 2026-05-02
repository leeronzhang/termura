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

    @State private var content = ""
    @State private var isLoading = true
    @State private var isModified = false
    @State private var errorMessage: String?
    @State private var viewMode: NoteViewMode = .reading
    @State private var isHoveringPath = false

    private var absolutePath: String {
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

    // MARK: - File I/O

    private func loadFile() async {
        let path = absolutePath
        let root = projectRoot
        // WHY: File reads must leave MainActor while enforcing project-root containment.
        // OWNER: loadFile owns this detached read and awaits the Result immediately.
        // TEARDOWN: The detached task ends after one read and does not escape this method.
        // TEST: Cover successful reads, containment rejection, and file-read failure.
        let result: Result<String, Error> = await Task.detached {
            if !path.hasPrefix("/") {
                let resolvedFile = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
                guard resolvedFile.hasPrefix(resolvedRoot + "/") || resolvedFile == resolvedRoot else {
                    return .failure(CocoaError(.fileReadNoPermission))
                }
            }
            return Result { try String(contentsOfFile: path, encoding: .utf8) }
        }.value
        switch result {
        case let .success(text):
            content = text
        case let .failure(error):
            logger.warning("Failed to read \(path): \(error.localizedDescription)")
            errorMessage = "Cannot read file"
        }
        isLoading = false
    }

    private func saveFile() {
        let path = absolutePath
        let root = projectRoot
        let text = content
        Task {
            do {
                // WHY: Saving must keep blocking file I/O off MainActor.
                // OWNER: The enclosing Task owns this detached write and awaits it.
                // TEARDOWN: The detached task ends after one write attempt.
                // TEST: Cover successful save, containment rejection, and failure.
                try await Task.detached {
                    if !path.hasPrefix("/") {
                        let resolvedFile = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                        let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
                        guard resolvedFile.hasPrefix(resolvedRoot + "/") || resolvedFile == resolvedRoot else {
                            throw CocoaError(.fileWriteNoPermission)
                        }
                    }
                    try text.write(toFile: path, atomically: true, encoding: .utf8)
                }.value
                isModified = false
                logger.info("Saved \(path)")
            } catch {
                logger.warning("Failed to save \(path): \(error.localizedDescription)")
            }
        }
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
