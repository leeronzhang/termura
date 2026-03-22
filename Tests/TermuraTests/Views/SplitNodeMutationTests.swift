import Testing
@testable import Termura

@Suite("SplitNodeMutation")
struct SplitNodeMutationTests {

    @Test func splitLeafSingleNode() {
        let target = SessionID()
        let newID = SessionID()
        let root = SplitNode.leaf(target)

        let result = SplitNodeMutations.splitLeaf(root: root, targetID: target, newID: newID, axis: .vertical)

        guard case .split(let axis, let first, let second) = result else {
            Issue.record("Expected .split")
            return
        }
        #expect(axis == .vertical)
        guard case .leaf(let firstID) = first else { Issue.record("Expected leaf"); return }
        guard case .leaf(let secondID) = second else { Issue.record("Expected leaf"); return }
        #expect(firstID == target)
        #expect(secondID == newID)
    }

    @Test func splitLeafInNestedTree() {
        let a = SessionID()
        let b = SessionID()
        let newID = SessionID()
        let root = SplitNode.split(.horizontal, .leaf(a), .leaf(b))

        let result = SplitNodeMutations.splitLeaf(root: root, targetID: b, newID: newID, axis: .vertical)

        guard case .split(_, let first, let second) = result else {
            Issue.record("Expected .split")
            return
        }
        // First child unchanged
        guard case .leaf(let firstID) = first else { Issue.record("Expected leaf"); return }
        #expect(firstID == a)
        // Second child is now a split
        guard case .split(let innerAxis, _, _) = second else {
            Issue.record("Expected nested split")
            return
        }
        #expect(innerAxis == .vertical)
    }

    @Test func splitLeafRespectsMaxDepth() {
        // Build a tree at maximum depth
        var node = SplitNode.leaf(SessionID())
        for _ in 0..<AppConfig.SplitPane.maxSplitDepth {
            node = .split(.horizontal, node, .leaf(SessionID()))
        }
        #expect(node.canSplit == false)

        let target = node.allSessionIDs[0]
        let newID = SessionID()
        let result = SplitNodeMutations.splitLeaf(root: node, targetID: target, newID: newID, axis: .vertical)
        // Should return unchanged tree
        #expect(result.allSessionIDs.count == node.allSessionIDs.count)
    }

    @Test func removeLeafCollapsesToSibling() {
        let a = SessionID()
        let b = SessionID()
        let root = SplitNode.split(.horizontal, .leaf(a), .leaf(b))

        let result = SplitNodeMutations.removeLeaf(root: root, targetID: a)
        guard case .leaf(let remaining) = result else {
            Issue.record("Expected single leaf after removal")
            return
        }
        #expect(remaining == b)
    }

    @Test func removeLeafSingleNodeReturnsNil() {
        let a = SessionID()
        let root = SplitNode.leaf(a)

        let result = SplitNodeMutations.removeLeaf(root: root, targetID: a)
        #expect(result == nil)
    }

    @Test func removeLeafNonexistentIDNoChange() {
        let a = SessionID()
        let root = SplitNode.leaf(a)
        let nonexistent = SessionID()

        let result = SplitNodeMutations.removeLeaf(root: root, targetID: nonexistent)
        guard case .leaf(let id) = result else {
            Issue.record("Expected leaf")
            return
        }
        #expect(id == a)
    }
}
