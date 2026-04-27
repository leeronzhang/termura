import Foundation

/// Manages the state and incremental mutations of a visible file tree.
/// Handles expansion tracking and provides a flat list for efficient list rendering.
@Observable
@MainActor
final class FileTreeManager {
    private(set) var expandedNodeIDs: Set<String> = []
    private(set) var hideIgnoredFiles: Bool = true

    /// Cached flat list of visible tree items.
    private(set) var flatVisibleItems: [FlatTreeItem] = []

    @ObservationIgnored private var tree: [FileTreeNode] = []
    @ObservationIgnored private var _unfilteredFlatItems: [FlatTreeItem] = []
    @ObservationIgnored private var _unfilteredDirty = true

    init(expandedNodeIDs: Set<String>, hideIgnoredFiles: Bool) {
        self.expandedNodeIDs = expandedNodeIDs
        self.hideIgnoredFiles = hideIgnoredFiles
    }

    func updateTree(_ newTree: [FileTreeNode]) {
        tree = newTree
        rebuildFlatVisibleItems()
    }

    func setHideIgnoredFiles(_ hide: Bool) {
        hideIgnoredFiles = hide
        if _unfilteredDirty {
            rebuildFlatVisibleItems()
        } else {
            applyIgnoreFilter()
        }
    }

    func setExpandedNodeIDs(_ ids: Set<String>) {
        expandedNodeIDs = ids
        _unfilteredDirty = true
        rebuildFlatVisibleItems()
    }

    func toggleExpand(_ node: FileTreeNode) {
        guard node.isDirectory else { return }
        _unfilteredDirty = true
        if expandedNodeIDs.contains(node.id) {
            expandedNodeIDs.remove(node.id)
            removeVisibleDescendants(of: node)
        } else {
            expandedNodeIDs.insert(node.id)
            insertVisibleChildren(of: node)
        }
    }

    private func rebuildFlatVisibleItems() {
        _unfilteredFlatItems = tree.flattenVisible(expandedIDs: expandedNodeIDs)
        _unfilteredDirty = false
        applyIgnoreFilter()
    }

    private func applyIgnoreFilter() {
        flatVisibleItems = hideIgnoredFiles ? _unfilteredFlatItems.filter { !$0.node.isGitIgnored } : _unfilteredFlatItems
    }

    private func insertVisibleChildren(of node: FileTreeNode) {
        guard let idx = flatVisibleItems.firstIndex(where: { $0.id == node.id }),
              let children = node.children else { return }
        var toInsert: [FlatTreeItem] = []
        appendVisibleNodes(children, depth: flatVisibleItems[idx].depth + 1, into: &toInsert)
        guard !toInsert.isEmpty else { return }
        flatVisibleItems.insert(contentsOf: toInsert, at: idx + 1)
    }

    private func removeVisibleDescendants(of node: FileTreeNode) {
        guard let idx = flatVisibleItems.firstIndex(where: { $0.id == node.id }) else { return }
        let depth = flatVisibleItems[idx].depth
        let start = idx + 1
        var end = start
        while end < flatVisibleItems.count && flatVisibleItems[end].depth > depth {
            end += 1
        }
        guard end > start else { return }
        flatVisibleItems.removeSubrange(start ..< end)
    }

    private func appendVisibleNodes(_ nodes: [FileTreeNode], depth: Int, into result: inout [FlatTreeItem]) {
        for node in nodes {
            if hideIgnoredFiles && node.isGitIgnored { continue }
            result.append(FlatTreeItem(node: node, depth: depth))
            if node.isDirectory, expandedNodeIDs.contains(node.id), let children = node.children {
                appendVisibleNodes(children, depth: depth + 1, into: &result)
            }
        }
    }
}
