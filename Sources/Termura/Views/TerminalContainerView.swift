// Exemption: This is the ONLY file permitted to import SwiftTerm in the Views layer.
// The NSViewRepresentable boundary is explicitly required by the architecture.
import AppKit
import SwiftTerm
import SwiftUI

/// NSViewRepresentable wrapper around SwiftTerm's LocalProcessTerminalView.
/// Acts as the bridge between SwiftUI layout and the AppKit terminal renderer.
struct TerminalContainerView: NSViewRepresentable {
    let viewModel: TerminalViewModel
    let engine: SwiftTermEngine
    let theme: ThemeColors

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = engine.terminalView
        applyTheme(theme, to: view)
        // Hide scrollbar entirely — scrolling still works via trackpad / mouse wheel.
        // This avoids a visible track strip regardless of the system "Show scroll bars" setting.
        if let scrollView = view.enclosingScrollView ?? findScrollView(in: view) {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }
        return view
    }

    /// Searches subviews for an embedded NSScrollView (SwiftTerm nests one internally).
    private func findScrollView(in view: NSView) -> NSScrollView? {
        for sub in view.subviews {
            if let sv = sub as? NSScrollView { return sv }
            if let sv = findScrollView(in: sub) { return sv }
        }
        return nil
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        applyTheme(theme, to: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Theme application

    private func applyTheme(_ theme: ThemeColors, to view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = NSColor(theme.background)
        view.nativeForegroundColor = NSColor(theme.foreground)
        view.installColors(theme.toSwiftTermColors())
    }
}

// MARK: - Coordinator

extension TerminalContainerView {
    /// @MainActor coordinator: handles resize and keyboard routing.
    @MainActor
    final class Coordinator: NSObject {
        private let viewModel: TerminalViewModel

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }
    }
}
