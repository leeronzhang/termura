import Foundation

/// Pure functions for mutating a `SplitNode` tree.
/// Keeps mutation logic testable and out of SwiftUI views.
enum SplitNodeMutations {
    /// Splits the leaf matching `targetID` into a new `.split` node
    /// containing the original leaf and a new leaf with `newID`.
    /// Returns the original tree unchanged if the target is not found
    /// or the tree has reached maximum depth.
    static func splitLeaf(
        root: SplitNode,
        targetID: SessionID,
        newID: SessionID,
        axis: SplitAxis
    ) -> SplitNode {
        guard root.canSplit else { return root }
        return replaceLeaf(node: root, targetID: targetID, newID: newID, axis: axis)
    }

    /// Removes the leaf matching `targetID` and collapses its parent split.
    /// Returns `nil` if the root itself is the target leaf (nothing remains).
    static func removeLeaf(root: SplitNode, targetID: SessionID) -> SplitNode? {
        switch root {
        case let .leaf(id):
            return id == targetID ? nil : root
        case let .split(axis, first, second):
            let newFirst = removeLeaf(root: first, targetID: targetID)
            let newSecond = removeLeaf(root: second, targetID: targetID)
            switch (newFirst, newSecond) {
            case (nil, nil):
                return nil
            case (nil, let remaining?):
                return remaining
            case (let remaining?, nil):
                return remaining
            case let (firstNode?, secondNode?):
                return .split(axis, firstNode, secondNode)
            }
        }
    }

    // MARK: - Private

    private static func replaceLeaf(
        node: SplitNode,
        targetID: SessionID,
        newID: SessionID,
        axis: SplitAxis
    ) -> SplitNode {
        switch node {
        case let .leaf(id):
            if id == targetID {
                return .split(axis, .leaf(id), .leaf(newID))
            }
            return node
        case let .split(a, first, second):
            let newFirst = replaceLeaf(node: first, targetID: targetID, newID: newID, axis: axis)
            let newSecond = replaceLeaf(node: second, targetID: targetID, newID: newID, axis: axis)
            return .split(a, newFirst, newSecond)
        }
    }
}
