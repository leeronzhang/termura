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

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let preview, let window else { return }
        window.makeFirstResponder(preview)
    }

    /// Termura's main window is AppKit-managed and uses a `Settings` SwiftUI
    /// Scene, so SwiftUI doesn't inject `EditCommands` and there's no global
    /// `Edit > Copy` menu item with the ⌘C key equivalent. Without that
    /// equivalent, `QLPreviewView` / `PDFView` never see ⌘C even when they
    /// are first responder. Catch the shortcut here and forward to whatever
    /// inside the preview implements `copy:` via `NSApp.sendAction(_:to:from:)`,
    /// which walks the responder chain just like a menu item would.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "c",
           NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
