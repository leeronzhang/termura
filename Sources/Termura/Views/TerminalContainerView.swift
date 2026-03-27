// Exemption: This is the ONLY file permitted to import SwiftTerm in the Views layer.
// The NSViewRepresentable boundary is explicitly required by the architecture.
import AppKit
import OSLog
import SwiftTerm
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalContainerView")

/// NSViewRepresentable wrapper around SwiftTerm's LocalProcessTerminalView.
/// Acts as the bridge between SwiftUI layout and the AppKit terminal renderer.
struct TerminalContainerView: NSViewRepresentable {
    let viewModel: TerminalViewModel
    let engine: any TerminalEngine
    let theme: ThemeColors
    /// Value types so SwiftUI diffs trigger updateNSView on change.
    let fontFamily: String
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = engine.terminalNSView
        view.autoresizingMask = [.width, .height]
        if let termView = view as? LocalProcessTerminalView {
            applyTheme(theme, to: termView)
        }
        hideScroller(in: view)
        // Register for file drops — handled via Coordinator.
        view.registerForDraggedTypes([.fileURL, .URL])
        context.coordinator.terminalNSView = view
        return view
    }

    /// Hides the legacy NSScroller that SwiftTerm adds directly as a subview.
    /// The scroller track is always visible with `.legacy` style, even when disabled,
    /// causing a lighter vertical strip at the terminal view's right edge.
    private func hideScroller(in view: NSView) {
        for sub in view.subviews where sub is NSScroller {
            sub.isHidden = true
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let termView = nsView as? LocalProcessTerminalView {
            applyTheme(theme, to: termView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Theme application

    private func applyTheme(_ theme: ThemeColors, to view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = NSColor(theme.background)
        view.nativeForegroundColor = NSColor(theme.foreground)
        view.installColors(theme.toSwiftTermColors())

        let font = NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.font = font
        logger.debug("Terminal font set: \(font.fontName) size=\(fontSize)")
    }
}

// MARK: - Coordinator

extension TerminalContainerView {
    /// @MainActor coordinator: handles drag-and-drop on the terminal NSView.
    @MainActor
    final class Coordinator: NSObject, NSDraggingDestination {
        private let viewModel: TerminalViewModel
        /// Set by makeNSView so the coordinator can forward drag events.
        weak var terminalNSView: NSView?

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }

        // MARK: - NSDraggingDestination

        func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard sender.draggingPasteboard.canReadObject(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) else {
                return []
            }
            return .copy
        }

        func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            guard let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], !urls.isEmpty else {
                return false
            }
            let paths = urls.map(\.path.shellEscaped).joined(separator: " ")
            viewModel.send(paths)
            return true
        }
    }
}
