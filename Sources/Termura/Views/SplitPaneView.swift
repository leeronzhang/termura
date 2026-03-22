import SwiftUI

/// Recursive split pane container supporting horizontal/vertical splits.
/// Each leaf holds a session ID rendered as a terminal; splits nest recursively.
struct SplitPaneView: View {
    @Binding var node: SplitNode
    let renderLeaf: (SessionID) -> AnyView

    var body: some View {
        switch node {
        case .leaf(let sessionID):
            renderLeaf(sessionID)
        case .split(let axis, _, _):
            splitView(axis: axis)
        }
    }

    @ViewBuilder
    private func splitView(axis: SplitAxis) -> some View {
        switch axis {
        case .horizontal:
            HSplitView {
                SplitPaneView(node: $node.first, renderLeaf: renderLeaf)
                    .frame(minWidth: AppConfig.SplitPane.minPaneWidth)
                SplitPaneView(node: $node.second, renderLeaf: renderLeaf)
                    .frame(minWidth: AppConfig.SplitPane.minPaneWidth)
            }
        case .vertical:
            VSplitView {
                SplitPaneView(node: $node.first, renderLeaf: renderLeaf)
                    .frame(minHeight: AppConfig.SplitPane.minPaneHeight)
                SplitPaneView(node: $node.second, renderLeaf: renderLeaf)
                    .frame(minHeight: AppConfig.SplitPane.minPaneHeight)
            }
        }
    }
}

// MARK: - Split Data Model

/// Axis for a split pane.
enum SplitAxis: String, Sendable, Codable {
    case horizontal
    case vertical
}

/// Recursive tree representing the split layout.
/// A leaf holds a single session; a split holds two children.
indirect enum SplitNode: Sendable {
    case leaf(SessionID)
    case split(SplitAxis, SplitNode, SplitNode)

    /// The depth of the deepest leaf.
    var depth: Int {
        switch self {
        case .leaf:
            return 0
        case .split(_, let first, let second):
            return 1 + max(first.depth, second.depth)
        }
    }

    /// Whether another split can be added without exceeding the max depth.
    var canSplit: Bool {
        depth < AppConfig.SplitPane.maxSplitDepth
    }

    /// All session IDs in this tree.
    var allSessionIDs: [SessionID] {
        switch self {
        case .leaf(let id):
            return [id]
        case .split(_, let first, let second):
            return first.allSessionIDs + second.allSessionIDs
        }
    }
}

// MARK: - Binding helpers for indirect enum

extension Binding where Value == SplitNode {
    var first: Binding<SplitNode> {
        Binding<SplitNode>(
            get: {
                if case .split(_, let f, _) = wrappedValue { return f }
                return wrappedValue
            },
            set: { newValue in
                if case .split(let axis, _, let second) = wrappedValue {
                    wrappedValue = .split(axis, newValue, second)
                }
            }
        )
    }

    var second: Binding<SplitNode> {
        Binding<SplitNode>(
            get: {
                if case .split(_, _, let s) = wrappedValue { return s }
                return wrappedValue
            },
            set: { newValue in
                if case .split(let axis, let first, _) = wrappedValue {
                    wrappedValue = .split(axis, first, newValue)
                }
            }
        )
    }
}
