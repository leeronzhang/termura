import AppKit
import SwiftUI

/// A 1pt visual divider with an 8pt drag hit zone for resizing adjacent panels.
///
/// - `dragFactor`:  +1.0 → dragging right widens the bound panel (left-side divider)
///                  -1.0 → dragging left widens the bound panel (right-side divider)
struct ResizableDivider: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    var dragFactor: Double = 1.0

    @State private var startWidth: Double?

    var body: some View {
        ZStack {
            Color(nsColor: .separatorColor)
                .frame(width: 1)
            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
                .gesture(resizeGesture)
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
        .frame(maxHeight: .infinity)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if startWidth == nil { startWidth = width }
                let proposed = (startWidth ?? width) + dragFactor * value.translation.width
                width = Swift.min(Swift.max(proposed, minWidth), maxWidth)
            }
            .onEnded { _ in startWidth = nil }
    }
}
