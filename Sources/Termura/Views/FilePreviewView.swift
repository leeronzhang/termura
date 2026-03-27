import AppKit
import QuickLookUI
import SwiftUI

/// Read-only file preview using macOS QuickLook.
/// Supports images, PDFs, Office documents, and dozens of other formats natively.
struct FilePreviewView: View {
    let filePath: String
    let projectRoot: String

    @State private var zoomScale: CGFloat = 1.0

    private var absoluteURL: URL {
        if filePath.hasPrefix("/") {
            return URL(fileURLWithPath: filePath)
        }
        return URL(fileURLWithPath: projectRoot).appendingPathComponent(filePath)
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
            previewHeader
            Divider()
            if isImage {
                ImagePreviewView(fileURL: absoluteURL, zoom: zoomScale)
            } else {
                QuickLookPreviewRepresentable(fileURL: absoluteURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewHeader: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "eye")
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
            Text(absoluteURL.lastPathComponent)
                .font(AppUI.Font.labelMono)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            if isImage {
                zoomControls
            }
            Button("Open in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([absoluteURL])
            }
            .font(AppUI.Font.label)
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
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
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Image Preview (scrollable, 1:1 default)

/// Renders an image at native pixel size (1:1), centered in the view.
/// Supports zoom via the header controls.
struct ImagePreviewView: NSViewRepresentable {
    let fileURL: URL
    let zoom: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter

        if let image = NSImage(contentsOf: fileURL) {
            imageView.image = image
            let size = image.size
            imageView.frame = NSRect(
                x: 0, y: 0,
                width: size.width * zoom,
                height: size.height * zoom
            )
        }

        scrollView.documentView = imageView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? NSImageView,
              let image = imageView.image ?? NSImage(contentsOf: fileURL) else { return }

        if imageView.image == nil {
            imageView.image = image
        }

        let size = image.size
        let newFrame = NSRect(
            x: 0, y: 0,
            width: size.width * zoom,
            height: size.height * zoom
        )
        if imageView.frame.size != newFrame.size {
            imageView.frame = newFrame
            scrollView.needsLayout = true
        }
    }
}

// MARK: - Centering Clip View

/// NSClipView subclass that centers the document view when it is smaller than the visible area.
/// Uses `constrainBoundsRect` — the idiomatic AppKit approach that cooperates with
/// NSScrollView's internal scroll management instead of fighting it via `setFrameOrigin`.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let docView = documentView else { return rect }

        let docFrame = docView.frame
        if rect.width > docFrame.width {
            rect.origin.x = (docFrame.width - rect.width) / 2
        }
        if rect.height > docFrame.height {
            rect.origin.y = (docFrame.height - rect.height) / 2
        }

        return rect
    }
}

// MARK: - QuickLook (for non-image files: PDF, docx, etc.)

struct QuickLookPreviewRepresentable: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view?.autostarts = true
        view?.previewItem = fileURL as QLPreviewItem
        return view ?? QLPreviewView()
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if nsView.previewItem as? URL != fileURL {
            nsView.previewItem = fileURL as QLPreviewItem
        }
    }
}
