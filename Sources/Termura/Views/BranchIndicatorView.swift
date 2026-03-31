import SwiftUI

/// Visual indicator for session tree branches: subtle vertical indent guides (IDE-style).
/// Lines are drawn as overlays at fixed x-positions so they align with the parent row's content edge.
struct BranchIndicatorView: View {
    let depth: Int
    let branchType: BranchType
    let hasChildren: Bool

    /// Per-level indent matching the tree node padding.
    static let indentPerLevel: CGFloat = 20

    /// X-offset of the first vertical line — aligns with root row's text left edge.
    private let firstLineOffset: CGFloat = AppUI.Spacing.xxxl

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0 ..< depth, id: \.self) { level in
                Rectangle()
                    .fill(Color.secondary.opacity(AppUI.Opacity.softBorder))
                    .frame(width: AppUI.Size.branchIndicatorLine)
                    .padding(.leading, firstLineOffset + CGFloat(level) * Self.indentPerLevel)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Branch Indicators") {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(0 ..< 4, id: \.self) { depth in
            ZStack {
                BranchIndicatorView(depth: depth, branchType: .main, hasChildren: depth < 3)
                Text("Depth \(depth)")
                    .font(.caption)
                    .padding(.leading, 8 + CGFloat(depth) * BranchIndicatorView.indentPerLevel)
            }
            .frame(height: 32)
        }
    }
    .frame(width: 200)
    .padding()
}
#endif
