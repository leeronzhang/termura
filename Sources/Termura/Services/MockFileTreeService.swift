import Foundation

/// Test double for `FileTreeServiceProtocol`.
actor MockFileTreeService: FileTreeServiceProtocol {
    var stubbedTree: [FileTreeNode] = []
    var scanCallCount = 0
    var annotateCallCount = 0

    func scan(at projectRoot: String) -> [FileTreeNode] {
        scanCallCount += 1
        return stubbedTree
    }

    func annotate(
        tree: [FileTreeNode],
        with gitResult: GitStatusResult,
        trackedFiles: Set<String>
    ) -> [FileTreeNode] {
        annotateCallCount += 1
        return tree
    }
}
