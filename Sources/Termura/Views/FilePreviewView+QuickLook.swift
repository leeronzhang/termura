import AppKit
import QuickLookUI
import SwiftUI

// MARK: - QuickLook (for non-image files: PDF, docx, etc.)

struct QuickLookPreviewRepresentable: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> QuickLookHostView {
        let host = QuickLookHostView()
        let preview = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        preview.autostarts = true
        preview.previewItem = fileURL as QLPreviewItem
        preview.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(preview)
        host.preview = preview
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            preview.topAnchor.constraint(equalTo: host.topAnchor),
            preview.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        return host
    }

    func updateNSView(_ nsView: QuickLookHostView, context: Context) {
        guard let preview = nsView.preview else { return }
        if preview.previewItem as? URL != fileURL {
            preview.previewItem = fileURL as QLPreviewItem
        }
    }
}

/// Hosts a `QLPreviewView` and promotes it to the window's first responder
/// once the view is mounted, so ⌘C reaches the preview's NSResponder
/// chain. Without this, SwiftUI's `NSViewRepresentable` wrapper leaves
/// the preview without keyboard focus and Cmd+C silently no-ops on
/// selected PDF / document text.
final class QuickLookHostView: NSView {
    weak var preview: QLPreviewView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let preview, let window else { return }
        window.makeFirstResponder(preview)
    }
}
