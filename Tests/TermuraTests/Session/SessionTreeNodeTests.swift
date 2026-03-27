import Testing
@testable import Termura

@Suite("SessionTreeNode")
struct SessionTreeNodeTests {

    @Test("Builds forest from flat records with parent links")
    func buildForest() {
        let root = SessionRecord(title: "Root")
        let child1 = SessionRecord(title: "Child 1", parentID: root.id, branchType: .investigation)
        let child2 = SessionRecord(title: "Child 2", parentID: root.id, branchType: .fix)
        let grandchild = SessionRecord(title: "Grandchild", parentID: child1.id, branchType: .review)

        let nodes = SessionTreeNode.buildForest(from: [root, child1, child2, grandchild])

        #expect(nodes.count == 1)
        #expect(nodes[0].record.title == "Root")
        #expect(nodes[0].children.count == 2)
        #expect(nodes[0].depth == 0)
        #expect(nodes[0].isRoot)

        let c1Node = nodes[0].children.first { $0.record.title == "Child 1" }
        #expect(c1Node != nil)
        #expect(c1Node?.depth == 1)
        #expect(c1Node?.isBranch == true)
        #expect(c1Node?.children.count == 1)
        #expect(c1Node?.children[0].record.title == "Grandchild")
        #expect(c1Node?.children[0].depth == 2)
    }

    @Test("Multiple roots create multiple trees")
    func multipleRoots() {
        let root1 = SessionRecord(title: "Root A")
        let root2 = SessionRecord(title: "Root B")
        let child = SessionRecord(title: "Child of A", parentID: root1.id)

        let nodes = SessionTreeNode.buildForest(from: [root1, root2, child])
        #expect(nodes.count == 2)
    }

    @Test("Empty records produce empty forest")
    func emptyForest() {
        let nodes = SessionTreeNode.buildForest(from: [])
        #expect(nodes.isEmpty)
    }

    @Test("Leaf nodes have no children")
    func leafNode() {
        let root = SessionRecord(title: "Root")
        let nodes = SessionTreeNode.buildForest(from: [root])
        #expect(nodes[0].hasChildren == false)
        #expect(nodes[0].children.isEmpty)
    }

    @Test("allSessionIDs in SplitNode")
    func splitNodeIDs() {
        let id1 = SessionID()
        let id2 = SessionID()
        let node = SplitNode.split(axis: .horizontal, first: .leaf(id1), second: .leaf(id2))
        #expect(node.allSessionIDs.count == 2)
        #expect(node.depth == 1)
        #expect(node.canSplit == true)
    }
}
