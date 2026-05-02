import AppKit
import OSLog
import SwiftUI
import VisionKit

private let logger = Logger(subsystem: "com.termura.app", category: "FilePreviewView+ImageOCR")

// MARK: - Image Preview (scrollable, 1:1 default, Live Text-enabled)

/// Renders an image at native pixel size (1:1), centered in the view.
/// Supports zoom via the header controls. A VisionKit
/// `ImageAnalysisOverlayView` sits on top so users can select recognised
/// text (Live Text / OCR) and ⌘C copies it to the pasteboard, matching
/// the system Photos / Preview behaviour.
struct ImagePreviewView: NSViewRepresentable {
    let fileURL: URL
    let zoom: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

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

        let overlay = ImageAnalysisOverlayView()
        overlay.preferredInteractionTypes = .textSelection
        overlay.autoresizingMask = [.width, .height]
        imageView.addSubview(overlay)
        context.coordinator.overlay = overlay

        if let image = NSImage(contentsOf: fileURL) {
            imageView.image = image
            let size = image.size
            let frame = NSRect(x: 0, y: 0, width: size.width * zoom, height: size.height * zoom)
            imageView.frame = frame
            overlay.frame = imageView.bounds
            context.coordinator.analyze(image: image)
        }

        scrollView.documentView = imageView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? NSImageView else { return }
        if imageView.image == nil, let image = NSImage(contentsOf: fileURL) {
            imageView.image = image
            context.coordinator.analyze(image: image)
        }
        guard let image = imageView.image else { return }
        let size = image.size
        let newFrame = NSRect(x: 0, y: 0, width: size.width * zoom, height: size.height * zoom)
        if imageView.frame.size != newFrame.size {
            imageView.frame = newFrame
            context.coordinator.overlay?.frame = imageView.bounds
            scrollView.needsLayout = true
        }
    }

    @MainActor
    final class Coordinator {
        weak var overlay: ImageAnalysisOverlayView?
        private let analyzer = ImageAnalyzer()
        private var lastAnalyzed: NSImage?

        func analyze(image: NSImage) {
            guard let overlay, lastAnalyzed !== image else { return }
            lastAnalyzed = image
            // WHY: VisionKit OCR is best-effort — if analysis fails the user
            //   still sees the image, just without selectable text.
            // OWNER: This coordinator owns the analysis Task; re-runs only
            //   when `updateNSView` swaps the image (different fileURL).
            // TEARDOWN: Each Task ends after one analysis; SwiftUI tears down
            //   the coordinator with the view.
            Task { @MainActor in
                do {
                    let configuration = ImageAnalyzer.Configuration([.text])
                    let analysis = try await analyzer.analyze(
                        image,
                        orientation: .up,
                        configuration: configuration
                    )
                    overlay.analysis = analysis
                } catch {
                    // Non-critical: image renders fine without Live Text.
                    logger.debug("Live Text analysis failed: \(error.localizedDescription)")
                }
            }
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
