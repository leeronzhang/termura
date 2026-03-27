import SwiftUI

// MARK: - Flat Tree Item (pre-computed for single-level rendering)

/// A flattened representation of a visible tree node, carrying its depth for indentation.
struct FlatTreeItem: Identifiable {
    let node: FileTreeNode
    let depth: Int
    var id: String { node.id }
}

// MARK: - Flatten helper

extension [FileTreeNode] {
    /// Walk the tree and return only nodes that are currently visible
    /// (i.e. all ancestors are expanded). Each item carries its depth.
    func flattenVisible(expandedIDs: Set<String>) -> [FlatTreeItem] {
        var result: [FlatTreeItem] = []
        func walk(_ nodes: [FileTreeNode], depth: Int) {
            for node in nodes {
                result.append(FlatTreeItem(node: node, depth: depth))
                if node.isDirectory, expandedIDs.contains(node.id),
                   let children = node.children {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(self, depth: 0)
        return result
    }
}

// MARK: - File Tree Row (non-recursive, single row)

struct FileTreeRowView: View {
    let node: FileTreeNode
    let depth: Int
    let isExpanded: Bool
    var isActive: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            // Indentation (fixed-width invisible block)
            if depth > 0 {
                Color.clear
                    .frame(
                        width: CGFloat(depth) * AppConfig.UI.fileTreeIndentPerLevel,
                        height: 1
                    )
            }

            // Directory: arrow only; File: file icon only
            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(AppUI.Font.chevron)
                    .foregroundColor(.secondary)
                    .frame(width: AppConfig.UI.fileTreeChevronWidth)
            } else {
                FileTypeIcon.image(for: node.name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: AppUI.Size.fileTypeIcon, height: AppUI.Size.fileTypeIcon)
                    .foregroundColor(fileColor)
            }

            Text(node.name)
                .font(AppUI.Font.title3)
                .foregroundColor(nameColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            // Git status badges
            if node.isDirectory && !node.gitChildStats.isEmpty {
                directoryStatsBadges
            } else if let status = node.gitStatus, !node.isDirectory {
                gitBadge(status, staged: node.isGitStaged)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.smMd)
        .background(isActive ? Color.accentColor.opacity(AppUI.Opacity.selected) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppUI.Radius.md)
                .stroke(isActive ? Color.accentColor.opacity(AppUI.Opacity.border) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Colors (Xcode-style: modified=orange, untracked/added=green, deleted=red)

    private var nameColor: Color {
        if node.isGitIgnored { return .secondary }
        guard let status = node.gitStatus else { return .primary }
        switch status {
        case .modified: return node.isGitStaged ? .green : .orange
        case .added: return .green
        case .untracked: return .cyan
        case .deleted: return .red
        case .renamed, .copied: return .blue
        }
    }

    private var directoryColor: Color {
        node.gitStatus != nil ? .orange : .secondary
    }

    private var fileColor: Color {
        if node.isGitIgnored { return .secondary }
        guard let status = node.gitStatus else { return .secondary }
        switch status {
        case .modified: return node.isGitStaged ? .green : .orange
        case .added, .untracked: return .green
        case .deleted: return .red
        case .renamed, .copied: return .blue
        }
    }

    private var directoryDotColor: Color {
        .orange
    }

    // MARK: - Directory stats badges (dot + count for each status kind)

    /// Display order for directory stat badges.
    private static let statDisplayOrder: [GitFileStatus.Kind] = [
        .modified, .added, .untracked, .deleted, .renamed, .copied
    ]

    private var directoryStatsBadges: some View {
        HStack(spacing: AppUI.Spacing.mdLg) {
            ForEach(Self.statDisplayOrder, id: \.rawValue) { kind in
                if let total = node.gitChildStats[kind], total > 0 {
                    Text("\(badgeLetter(kind))\(total)")
                        .font(AppUI.Font.labelMono.weight(.semibold))
                        .foregroundColor(badgeColor(kind, staged: false))
                }
            }
        }
    }

    // MARK: - Git badge (monospaced, right-aligned)

    private func gitBadge(_ kind: GitFileStatus.Kind, staged: Bool) -> some View {
        Text(badgeLetter(kind))
            .font(AppUI.Font.labelMono.weight(.semibold))
            .foregroundColor(badgeColor(kind, staged: staged))
            .frame(width: AppUI.Size.iconFrame, alignment: .trailing)
    }

    private func badgeLetter(_ kind: GitFileStatus.Kind) -> String {
        switch kind {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .untracked: "U"
        case .renamed, .copied: "R"
        }
    }

    private func badgeColor(_ kind: GitFileStatus.Kind, staged: Bool) -> Color {
        switch kind {
        case .modified: staged ? .green : .orange
        case .added: .green
        case .untracked: .cyan
        case .deleted: .red
        case .renamed, .copied: .blue
        }
    }
}
