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
    /// `Edit > Copy` menu item with the ⌘C key equivalent. Catch the shortcut
    /// here and route it to the inner content view (PDFView / NSTextView)
    /// directly — see `copyTarget()` for why a plain responder-chain hop fails.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "c",
           let target = copyTarget(),
           NSApplication.shared.sendAction(#selector(NSText.copy(_:)), to: target, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Right-click anywhere in the preview shows a single "Copy" item that
    /// routes to the same descendant responder as ⌘C. Always enabled — like
    /// macOS Preview.app, the action is a no-op when nothing is selected.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: String(localized: "Copy"), action: #selector(forwardCopy(_:)), keyEquivalent: "c")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func forwardCopy(_ sender: Any?) {
        guard let target = copyTarget() else { return }
        NSApplication.shared.sendAction(#selector(NSText.copy(_:)), to: target, from: self)
    }

    /// `QLPreviewView` is a container that swaps in a per-format content view
    /// (PDFView for PDFs, NSTextView for plaintext, etc.). Those content views
    /// implement `copy:`, but `QLPreviewView` itself does not. The system
    /// responder chain walks UP from first responder and never DOWN into
    /// `QLPreviewView`'s private subtree, so `sendAction(copy:, to: nil)`
    /// silently no-ops. Resolve the target ourselves with a depth-first walk
    /// that prefers the deepest descendant implementing `copy:`.
    private func copyTarget() -> NSResponder? {
        guard let preview else { return nil }
        return Self.deepestResponder(in: preview, implementing: #selector(NSText.copy(_:)))
    }

    private static func deepestResponder(in view: NSView, implementing selector: Selector) -> NSResponder? {
        for sub in view.subviews {
            if let found = deepestResponder(in: sub, implementing: selector) { return found }
        }
        return view.responds(to: selector) ? view : nil
    }
}
