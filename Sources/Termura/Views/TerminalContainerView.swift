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
        // SwiftTerm uses a bare NSScroller subview (not NSScrollView), so we find and hide it directly.
        hideScroller(in: view)
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
