import AppKit
import SwiftUI

/// Tags the hosting Settings NSWindow with `.fullScreenAuxiliary` so it can be
/// shown alongside a fullscreen main window (instead of macOS swapping back to
/// the desktop Space when the user opens Settings via Cmd+,).
///
/// SwiftUI's `Settings { ... }` scene creates an NSWindow whose default
/// collectionBehavior gives it its own Space; this view re-enters that Space
/// the first time it is added to a window.
struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowWatchingView(frame: .zero)
        view.onAttach = { window in
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Bare NSView subclass that fires a callback once it is parented into an
/// NSWindow. viewDidMoveToWindow is the earliest reliable hook — relying on
/// makeNSView's return point would race the view-hierarchy attach.
private final class WindowWatchingView: NSView {
    var onAttach: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        onAttach?(window)
    }
}
