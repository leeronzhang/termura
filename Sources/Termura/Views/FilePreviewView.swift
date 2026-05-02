import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "FilePreviewView")

/// Read-only file preview using macOS QuickLook.
/// Supports images, PDFs, Office documents, and dozens of other formats natively.
struct FilePreviewView: View {
    let filePath: String
    let projectRoot: String

    @Environment(\.commandRouter) private var commandRouter
    @State private var zoomScale: CGFloat = 1.0
    @State private var isPathBlocked = false
    @State private var isHoveringPath = false

    private var absoluteURL: URL {
        if filePath.hasPrefix("/") {
            return URL(fileURLWithPath: filePath)
        }
        return URL(fileURLWithPath: projectRoot).appendingPathComponent(filePath).standardized
    }

    /// Image extensions that benefit from 1:1 pixel rendering.
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "ico", "svg"
    ]

    private var isImage: Bool {
        Self.imageExtensions.contains(absoluteURL.pathExtension.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            if isPathBlocked {
                Spacer()
                Text("File path escapes project root")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                previewHeader
                Divider()
                if isImage {
                    ImagePreviewView(fileURL: absoluteURL, zoom: zoomScale)
                } else {
                    QuickLookPreviewRepresentable(fileURL: absoluteURL)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await validateContainment() }
    }

    /// Validates that the resolved file path stays within the project root.
    /// Uses resolvingSymlinksInPath (I/O) off-MainActor to detect symlink attacks.
    private func validateContainment() async {
        guard !filePath.hasPrefix("/") else { return }
        let url = absoluteURL
        let root = projectRoot
        // WHY: Symlink resolution can touch disk and must stay off MainActor during path validation.
        // OWNER: validateContainment owns this detached check and awaits it inline.
        // TEARDOWN: The detached task exits after one containment decision.
        // TEST: Cover traversal rejection and valid in-project previews.
        let blocked: Bool = await Task.detached {
            let resolvedFile = url.resolvingSymlinksInPath().path
            let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
            return !(resolvedFile.hasPrefix(resolvedRoot + "/") || resolvedFile == resolvedRoot)
        }.value
        if blocked {
            logger.warning("Path traversal blocked in FilePreview: \(filePath, privacy: .public)")
            isPathBlocked = true
        }
    }

    private var previewHeader: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "eye")
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
            Text(absoluteURL.lastPathComponent)
                .font(AppUI.Font.labelMono)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            copyPathButton
            Spacer()
            if isImage {
                zoomControls
            }
            Button("Open in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([absoluteURL])
            }
            .font(AppUI.Font.label)
            .buttonStyle(.plain)
            .foregroundColor(.brandGreen)
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringPath = hovering
            }
        }
    }

    /// Hover-revealed shortcut: one click copies `<filename>\n<absolute path>`
    /// to the system pasteboard. Mirrors the affordance in CodeEditorView and
    /// MarkdownFileView so the preview path bar feels the same.
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
        let path = absoluteURL.path
        let fileName = absoluteURL.lastPathComponent
        let payload = "\(fileName)\n\(path)"
        // §3.2 exception: NSPasteboard is a platform bridge invoked from
        // the view layer (matches existing usages in CodeEditorView /
        // MarkdownFileView). Future PasteboardService extraction is
        // tracked separately.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(payload, forType: .string)
        commandRouter.showToast(didWrite ? "Copied filename and path" : "Copy failed")
    }

    private var zoomControls: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            Button {
                zoomScale = max(zoomScale - AppConfig.UI.previewZoomStep, AppConfig.UI.previewZoomMin)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Text("\(Int(zoomScale * 100))%")
                .font(AppUI.Font.captionMono)
                .foregroundColor(.secondary)
                .frame(width: AppConfig.UI.filePreviewLineNumberWidth, alignment: .center)

            Button {
                zoomScale = min(zoomScale + AppConfig.UI.previewZoomStep, AppConfig.UI.previewZoomMax)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                zoomScale = 1.0
            } label: {
                Text("1:1")
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.brandGreen)
            }
            .buttonStyle(.plain)
        }
    }
}

// `ImagePreviewView` lives in `FilePreviewView+ImageOCR.swift` (image
// + Live Text overlay + centering clip view). `QuickLookPreviewRepresentable`
// lives in `FilePreviewView+QuickLook.swift` (PDF / docx / etc).
// Splitting keeps this file under the SwiftLint file-length budget while
// preserving the public API (`ImagePreviewView`, `QuickLookPreviewRepresentable`).
