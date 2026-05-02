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
    @Environment(\.fontSettings) var fontSettings
    @Environment(\.commandRouter) private var commandRouter

    @State private var content = ""
    @State private var isLoading = false
    @State private var isModified = false
    @State private var errorMessage: String?
    @State private var isHoveringPath = false

    private var absolutePath: String {
        if filePath.hasPrefix("/") { return filePath }
        return URL(fileURLWithPath: projectRoot).appendingPathComponent(filePath).standardized.path
    }

    /// Full breadcrumb path: "Sources > Termura > Views > CodeEditorView.swift"
    private var breadcrumbComponents: [String] {
        let raw = filePath.hasPrefix("/")
            ? MetadataFormatter.abbreviateDirectory(filePath)
            : filePath
        return raw.split(separator: "/").map(String.init)
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
        "md": "markdown", "markdown": "markdown"
    ]

    var body: some View {
        VStack(spacing: 0) {
            fileEditorPathBar
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

    private var fileEditorPathBar: some View {
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
            copyPathButton
                .padding(.leading, AppUI.Spacing.md)
            if isModified {
                Circle()
                    .fill(Color.orange)
                    .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
            }
            Spacer()
            if isModified {
                Button("Save") { saveFile() }
                    .font(AppUI.Font.label)
                    .buttonStyle(.plain)
                    .foregroundColor(.brandGreen)
            }
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

    /// One-click "copy filename + absolute path" affordance shown on hover.
    /// Sits next to the breadcrumb so the user can either select a path
    /// segment manually (⌘C copies the selection) or click here to grab
    /// both pieces in a single, predictable format.
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
        // the view layer (matches existing usages in EditorTextView /
        // RemoteControlSettingsView). Future PasteboardService extraction
        // tracked separately.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(payload, forType: .string)
        commandRouter.showToast(didWrite ? "Copied filename and path" : "Copy failed")
    }

    /// Checks whether `filePath` resolves within `rootPath` after symlink resolution.
    /// Must be called off-MainActor (resolvingSymlinksInPath performs I/O).
    private nonisolated static func isContained(filePath: String, inRoot rootPath: String) -> Bool {
        let resolvedFile = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
        let resolvedRoot = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().path
        return resolvedFile.hasPrefix(resolvedRoot + "/") || resolvedFile == resolvedRoot
    }

    private func loadFile() async {
        let path = absolutePath
        let root = projectRoot
        // WHY: File reads must leave MainActor while still enforcing project-root containment.
        // OWNER: loadFile owns this detached read and awaits the Result immediately.
        // TEARDOWN: The detached task ends after one read attempt and does not escape this method.
        // TEST: Cover successful reads, containment rejection, and file-read failure handling.
        let result: Result<String, Error> = await Task.detached {
            // Absolute paths (harness rules) bypass root containment.
            if !path.hasPrefix("/"), !Self.isContained(filePath: path, inRoot: root) {
                return .failure(CocoaError(.fileReadNoPermission))
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
        // Task { } inherits @MainActor; I/O is offloaded via inner Task.detached so the
        // main thread is not blocked, and state update after the await is safely on MainActor.
        Task {
            do {
                // WHY: Saving must keep blocking file I/O off MainActor while preserving containment checks.
                // OWNER: The enclosing Task owns this detached write and awaits it before mutating UI state.
                // TEARDOWN: The detached task ends after one write attempt and does not outlive saveFile().
                // TEST: Cover successful save, containment rejection, and file-write failure handling.
                try await Task.detached {
                    if !path.hasPrefix("/"), !Self.isContained(filePath: path, inRoot: root) {
                        throw CocoaError(.fileWriteNoPermission)
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
}

// MARK: - Shared error view

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
