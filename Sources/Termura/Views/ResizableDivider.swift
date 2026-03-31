import AppKit
import SwiftUI

/// Transparent NSView that prevents isMovableByWindowBackground from intercepting
/// mouse drags on the resize hit zone.
private struct NonMovableView: NSViewRepresentable {
    func makeNSView(context: Context) -> BaseView { BaseView() }
    func updateNSView(_ nsView: BaseView, context: Context) {}

    final class BaseView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

/// A thin visual divider with an invisible wider drag hit zone for resizing adjacent panels.
struct ResizableDivider: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    var dragFactor: Double = 1.0
    var showLine: Bool = true
    /// When the dragged width falls below this threshold, `onCollapse` fires instead of clamping.
    var collapseThreshold: Double?
    var onCollapse: (() -> Void)?

    @State private var startWidth: Double?

    var body: some View {
        Group {
            if showLine {
                Color(nsColor: .separatorColor)
                    .frame(width: AppConfig.UI.dividerLineWidth)
            }
        }
        // Zero layout width when hidden, 1pt when visible.
        // Hit-testing extends 4pt on each side via the overlay.
        .frame(maxHeight: .infinity)
        .overlay {
            Color.clear
                .frame(width: AppConfig.UI.dividerHitTarget)
                .contentShape(Rectangle())
                .background(NonMovableView())
                .gesture(resizeGesture)
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if startWidth == nil { startWidth = width }
                let proposed = (startWidth ?? width) + dragFactor * value.translation.width
                if let threshold = collapseThreshold, proposed < threshold {
                    // Reset so subsequent drag events don't re-trigger before the sidebar animates away.
                    startWidth = nil
                    onCollapse?()
                    return
                }
                let clamped = Swift.min(Swift.max(proposed, minWidth), maxWidth)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    width = clamped
                }
            }
            .onEnded { _ in startWidth = nil }
    }
}
