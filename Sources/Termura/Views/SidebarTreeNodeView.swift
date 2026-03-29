import SwiftUI

// MARK: - Recursive tree node

struct SidebarTreeNodeView: View {
    let node: SessionTreeNode
    let sessionStore: SessionStore
    let sessionRow: (SessionRecord, (() -> Void)?, Bool) -> AnyView

    @State private var isExpanded = true

    var body: some View {
        if !node.record.isPinned {
            sessionRow(
                node.record,
                node.hasChildren ? {
                    withAnimation(.easeOut(duration: AppUI.Animation.quick)) {
                        isExpanded.toggle()
                    }
                } : nil,
                isExpanded
            )
            .padding(.leading, CGFloat(node.depth) * BranchIndicatorView.indentPerLevel)
            .overlay(alignment: .leading) {
                if node.depth > 0 {
                    BranchIndicatorView(
                        depth: node.depth,
                        branchType: node.record.branchType,
                        hasChildren: node.hasChildren
                    )
                }
            }

            if isExpanded {
                ForEach(node.children) { child in
                    SidebarTreeNodeView(
                        node: child,
                        sessionStore: sessionStore,
                        sessionRow: sessionRow
                    )
                }
            }
        }
    }
}
