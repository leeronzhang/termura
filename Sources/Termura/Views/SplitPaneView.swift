import SwiftUI

/// Recursive split pane container supporting horizontal/vertical splits.
/// Each leaf holds a session ID rendered as a terminal; splits nest recursively.
struct SplitPaneView: View {
    @Binding var node: SplitNode
    let renderLeaf: (SessionID) -> AnyView

    var body: some View {
        switch node {
        case let .leaf(sessionID):
            renderLeaf(sessionID)
        case let .split(axis, _, _):
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
            0
        case let .split(_, first, second):
            1 + max(first.depth, second.depth)
        }
    }

    /// Whether another split can be added without exceeding the max depth.
    var canSplit: Bool {
        depth < AppConfig.SplitPane.maxSplitDepth
    }

    /// All session IDs in this tree.
    var allSessionIDs: [SessionID] {
        switch self {
        case let .leaf(id):
            [id]
        case let .split(_, first, second):
            first.allSessionIDs + second.allSessionIDs
        }
    }
}

// MARK: - Binding helpers for indirect enum

extension Binding where Value == SplitNode {
    var first: Binding<SplitNode> {
        Binding<SplitNode>(
            get: {
                if case let .split(_, firstNode, _) = wrappedValue { return firstNode }
                return wrappedValue
            },
            set: { newValue in
                if case let .split(axis, _, secondNode) = wrappedValue {
                    wrappedValue = .split(axis, newValue, secondNode)
                }
            }
        )
    }

    var second: Binding<SplitNode> {
        Binding<SplitNode>(
            get: {
                if case let .split(_, _, secondNode) = wrappedValue { return secondNode }
                return wrappedValue
            },
            set: { newValue in
                if case let .split(axis, firstNode, _) = wrappedValue {
                    wrappedValue = .split(axis, firstNode, newValue)
                }
            }
        )
    }
}
