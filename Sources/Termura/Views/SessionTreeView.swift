import SwiftUI

/// Tree-structured session list replacing the flat sidebar list.
/// Renders `SessionTreeNode` recursively with indentation and branch indicators.
struct SessionTreeView: View {
    let nodes: [SessionTreeNode]
    let activeSessionID: SessionID?
    let onActivate: (SessionID) -> Void
    let onRename: (SessionID, String) -> Void
    let onCreateBranch: (SessionID, BranchType) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(nodes) { node in
                    SessionTreeRowView(
                        node: node,
                        activeSessionID: activeSessionID,
                        onActivate: onActivate,
                        onRename: onRename,
                        onCreateBranch: onCreateBranch
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Recursive row that type-erases children to break opaque return type cycle.
private struct SessionTreeRowView: View {
    let node: SessionTreeNode
    let activeSessionID: SessionID?
    let onActivate: (SessionID) -> Void
    let onRename: (SessionID, String) -> Void
    let onCreateBranch: (SessionID, BranchType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if node.depth > 0 {
                    BranchIndicatorView(
                        depth: node.depth,
                        branchType: node.record.branchType,
                        hasChildren: node.hasChildren
                    )
                }

                SessionRowView(
                    session: node.record,
                    isActive: activeSessionID == node.id,
                    hasUnreadFailure: false,
                    onActivate: { onActivate(node.id) },
                    onRename: { onRename(node.id, $0) }
                )
                .contextMenu {
                    branchContextMenu
                }
            }

            // Break recursion via AnyView
            ForEach(node.children) { child in
                AnyView(
                    SessionTreeRowView(
                        node: child,
                        activeSessionID: activeSessionID,
                        onActivate: onActivate,
                        onRename: onRename,
                        onCreateBranch: onCreateBranch
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var branchContextMenu: some View {
        if node.record.branchType == .main {
            Menu("New Branch") {
                ForEach(BranchType.allCases.filter { $0 != .main }, id: \.self) { type in
                    Button(type.rawValue.capitalized) {
                        onCreateBranch(node.id, type)
                    }
                }
            }
            Divider()
        }

        if node.isBranch {
            Button("Back to Parent") {
                if let parentID = node.record.parentID {
                    onActivate(parentID)
                }
            }
        }
    }
}
