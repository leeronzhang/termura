import Foundation

/// Recursive tree node wrapping a `SessionRecord` for tree-based UI rendering.
/// Built from flat `[SessionRecord]` by grouping on `parentID`.
struct SessionTreeNode: Identifiable, Sendable {
    let record: SessionRecord
    let children: [SessionTreeNode]
    let depth: Int

    var id: SessionID { record.id }
    var isRoot: Bool { record.parentID == nil }
    var isBranch: Bool { record.branchType != .main }
    var hasChildren: Bool { !children.isEmpty }

    /// Build a forest of tree nodes from a flat list of session records.
    static func buildForest(from records: [SessionRecord]) -> [SessionTreeNode] {
        let byParent = Dictionary(grouping: records) { $0.parentID }
        let roots = records.filter { $0.parentID == nil }
        return roots.map { buildNode(record: $0, byParent: byParent, depth: 0) }
    }

    private static func buildNode(
        record: SessionRecord,
        byParent: [SessionID?: [SessionRecord]],
        depth: Int
    ) -> SessionTreeNode {
        let childRecords = byParent[record.id] ?? []
        let childNodes = childRecords.map { child in
            buildNode(record: child, byParent: byParent, depth: depth + 1)
        }
        return SessionTreeNode(record: record, children: childNodes, depth: depth)
    }
}
