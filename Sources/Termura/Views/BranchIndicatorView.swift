import SwiftUI

/// Visual indicator for session tree branches: depth-based indentation + type icon.
struct BranchIndicatorView: View {
    let depth: Int
    let branchType: BranchType
    let hasChildren: Bool

    private let indentPerLevel: CGFloat = DS.Spacing.xl

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Spacer()
                .frame(width: CGFloat(depth) * indentPerLevel)

            branchLine

            branchIcon
                .font(DS.Font.caption)
                .foregroundColor(branchColor)
        }
        .frame(width: CGFloat(depth) * indentPerLevel + DS.Spacing.xxxl)
    }

    private var branchLine: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 10))
            path.addLine(to: CGPoint(x: 8, y: 10))
        }
        .stroke(branchColor.opacity(DS.Opacity.dimmed), lineWidth: 1)
        .frame(width: DS.Spacing.md, height: DS.Spacing.xxl)
    }

    private var branchIcon: some View {
        Image(systemName: iconName)
    }

    private var iconName: String {
        switch branchType {
        case .main: return "circle.fill"
        case .investigation: return "magnifyingglass"
        case .fix: return "wrench.fill"
        case .review: return "eye.fill"
        case .experiment: return "flask.fill"
        }
    }

    private var branchColor: Color {
        switch branchType {
        case .main: return .primary
        case .investigation: return .blue
        case .fix: return .orange
        case .review: return .green
        case .experiment: return .purple
        }
    }
}
