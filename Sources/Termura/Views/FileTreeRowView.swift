import SwiftUI

// MARK: - File Tree Row

struct FileTreeRowView: View {
    let node: FileTreeNode
    let depth: Int
    @Binding var expandedIDs: Set<String>
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    private var isExpanded: Bool {
        expandedIDs.contains(node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
            if node.isDirectory && isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeRowView(
                        node: child,
                        depth: depth + 1,
                        expandedIDs: $expandedIDs,
                        onOpenFile: onOpenFile
                    )
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            // Indentation
            if depth > 0 {
                Spacer()
                    .frame(width: CGFloat(depth) * AppConfig.UI.fileTreeIndentPerLevel)
            }

            // Folder chevron or file icon
            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(AppUI.Font.chevron)
                    .foregroundColor(.secondary)
                    .frame(width: AppConfig.UI.fileTreeChevronWidth)
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(AppUI.Font.label)
                    .foregroundColor(directoryColor)
            } else {
                Spacer().frame(width: AppConfig.UI.fileTreeChevronWidth)
                Image(systemName: "doc")
                    .font(AppUI.Font.label)
                    .foregroundColor(fileColor)
            }

            Text(node.name)
                .font(AppUI.Font.title3)
                .foregroundColor(nameColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Git status: folders get a colored dot, files get a letter badge
            if let status = node.gitStatus {
                Group {
                    if node.isDirectory {
                        Circle()
                            .fill(directoryDotColor)
                            .frame(width: 7, height: 7)
                    } else {
                        gitBadge(status, staged: node.isGitStaged)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.smMd)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedIDs.contains(node.id) {
                        expandedIDs.remove(node.id)
                    } else {
                        expandedIDs.insert(node.id)
                    }
                }
            } else {
                openFile()
            }
        }
    }

    // MARK: - Colors (Xcode-style: modified=orange, untracked/added=green, deleted=red)

    private var nameColor: Color {
        guard let status = node.gitStatus else { return .primary }
        if node.isDirectory { return .primary }
        switch status {
        case .modified: return node.isGitStaged ? .green : .orange
        case .added: return .green
        case .untracked: return .green
        case .deleted: return .red
        case .renamed, .copied: return .blue
        }
    }

    private var directoryColor: Color {
        node.gitStatus != nil ? .orange : .secondary
    }

    private var fileColor: Color {
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

    // MARK: - Git badge (monospaced, right-aligned)

    private func gitBadge(_ kind: GitFileStatus.Kind, staged: Bool) -> some View {
        Text(badgeLetter(kind))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(badgeColor(kind, staged: staged))
            .frame(width: 16, alignment: .trailing)
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
        case .untracked: .green
        case .deleted: .red
        case .renamed, .copied: .blue
        }
    }

    // MARK: - Actions

    private func openFile() {
        if let status = node.gitStatus {
            let untracked = status == .untracked
            onOpenFile?(node.relativePath, .diff(staged: node.isGitStaged, untracked: untracked))
        } else {
            onOpenFile?(node.relativePath, .edit)
        }
    }
}
