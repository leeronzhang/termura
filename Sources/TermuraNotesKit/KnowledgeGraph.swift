import Foundation

/// Node in the knowledge graph visualization.
public struct GraphNode: Codable, Hashable, Sendable {
    public enum NodeType: String, Codable, Sendable {
        case note
        case tag
    }

    public let id: String
    public let type: NodeType
    public let label: String
    /// Number of connections (backlinks + tags for notes, note count for tags).
    /// Used to scale the node radius in the D3 visualization.
    public let weight: Int

    public init(id: String, type: NodeType, label: String, weight: Int) {
        self.id = id
        self.type = type
        self.label = label
        self.weight = weight
    }
}

/// Edge in the knowledge graph visualization.
public struct GraphLink: Codable, Hashable, Sendable {
    public enum LinkType: String, Codable, Sendable {
        case backlink
        case tag
    }

    public let source: String
    public let target: String
    public let type: LinkType

    public init(source: String, target: String, type: LinkType) {
        self.source = source
        self.target = target
        self.type = type
    }
}

/// Complete graph data ready for D3.js serialization.
public struct KnowledgeGraphData: Codable, Sendable {
    public let nodes: [GraphNode]
    public let links: [GraphLink]

    public init(nodes: [GraphNode], links: [GraphLink]) {
        self.nodes = nodes
        self.links = links
    }

    /// Build graph data from notes and their backlink index.
    ///
    /// Nodes: one per note + one per unique tag.
    /// Links: note↔note for backlinks, note→tag for tag membership.
    public static func build(from notes: [NoteRecord], backlinkIndex: BacklinkIndex) -> KnowledgeGraphData {
        var nodes: [GraphNode] = []
        var links: [GraphLink] = []
        var tagCounts: [String: Int] = [:]
        var seenBacklinks = Set<String>()

        // Count tag usage for weight calculation.
        for note in notes {
            for tag in note.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        // Note nodes + tag links.
        for note in notes {
            let noteID = "note:\(note.id.rawValue)"
            let backlinkCount = backlinkIndex.backlinks(for: note.title).count
            let weight = backlinkCount + note.tags.count
            nodes.append(GraphNode(id: noteID, type: .note, label: note.title, weight: max(weight, 1)))

            for tag in note.tags {
                let tagID = "tag:\(tag)"
                links.append(GraphLink(source: noteID, target: tagID, type: .tag))
            }

            // Backlink edges (deduplicated, undirected).
            for backlink in backlinkIndex.backlinks(for: note.title) {
                let sourceID = "note:\(backlink.id.rawValue)"
                let pairKey = [sourceID, noteID].sorted().joined(separator: "↔")
                guard seenBacklinks.insert(pairKey).inserted else { continue }
                links.append(GraphLink(source: sourceID, target: noteID, type: .backlink))
            }
        }

        // Tag nodes.
        for (tag, count) in tagCounts {
            nodes.append(GraphNode(id: "tag:\(tag)", type: .tag, label: tag, weight: count))
        }

        return KnowledgeGraphData(nodes: nodes, links: links)
    }
}
