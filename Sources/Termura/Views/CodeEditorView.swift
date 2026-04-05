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

    @State private var content = ""
    @State private var isLoading = false
    @State private var isModified = false
    @State private var errorMessage: String?

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
            }
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
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
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

// MARK: - Binding-backed editor (for notes stored in GRDB)

/// Editable code viewer backed by a text Binding (no file I/O).
/// Used for notes whose content lives in the database.
struct NoteEditorView: View {
    let title: String
    let filePath: String?
    @Binding var text: String
    @Environment(\.fontSettings) var fontSettings

    @State private var isModified = false

    var body: some View {
        VStack(spacing: 0) {
            noteEditorPathBar
            Divider()
            CodeEditorTextViewRepresentable(
                text: $text,
                isModified: $isModified,
                onSave: {},
                fontFamily: fontSettings.terminalFontFamily,
                fontSize: fontSettings.editorFontSize,
                language: "markdown"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noteEditorPathBar: some View {
        HStack(spacing: AppUI.Spacing.md) {
            if let filePath {
                Button {
                    NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                } label: {
                    Text(MetadataFormatter.abbreviateDirectory(filePath))
                        .font(AppUI.Font.pathMono)
                        .foregroundColor(.secondary.opacity(AppUI.Opacity.strong))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
            Spacer()
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
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
