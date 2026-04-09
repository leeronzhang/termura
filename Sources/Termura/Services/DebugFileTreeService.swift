import Foundation

#if DEBUG

/// Debug fallback for previews and local environment defaults.
actor DebugFileTreeService: FileTreeServiceProtocol {
    var stubbedTree: [FileTreeNode] = []

    func scan(at projectRoot: String) -> [FileTreeNode] {
        stubbedTree
    }

    func annotate(
        tree: [FileTreeNode],
        with gitResult: GitStatusResult,
        trackedFiles: Set<String>
    ) -> [FileTreeNode] {
        tree
    }
}

#endif
