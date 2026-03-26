import SwiftUI

// MARK: - File Tree Row

struct FileTreeRowView: View {
    let node: FileTreeNode
    let depth: Int
    @Binding var expandedIDs: Set<String>
    var activeFilePath: String?
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    private var isExpanded: Bool {
        expandedIDs.contains(node.id)
    }

    private var isActive: Bool {
        guard let active = activeFilePath, !node.isDirectory else { return false }
        return node.relativePath == active
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
                        activeFilePath: activeFilePath,
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

            // Directory: arrow only (no folder icon); File: file icon only (no arrow)
            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(AppUI.Font.chevron)
                    .foregroundColor(.secondary)
                    .frame(width: AppConfig.UI.fileTreeChevronWidth)
            } else {
                FileTypeIcon.image(for: node.name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
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
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.smMd)
        .background(isActive ? Color.accentColor.opacity(AppUI.Opacity.selected) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppUI.Radius.md)
                .stroke(isActive ? Color.accentColor.opacity(AppUI.Opacity.border) : .clear, lineWidth: 1)
        )
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

    /// File extensions that should open in the code editor (text-based).
    private static let textExtensions: Set<String> = [
        "swift", "m", "h", "c", "cpp", "rs", "go", "py", "rb", "js", "ts",
        "jsx", "tsx", "json", "yaml", "yml", "toml", "xml", "plist",
        "html", "css", "scss", "less", "sh", "bash", "zsh", "fish",
        "md", "markdown", "txt", "log", "env", "gitignore", "editorconfig",
        "lock", "resolved", "cfg", "ini", "conf", "sql", "graphql",
        "vue", "svelte", "astro", "r", "lua", "zig", "nim", "ex", "exs",
        "java", "kt", "scala", "dart", "php", "pl", "pm"
    ]

    private var isTextFile: Bool {
        let ext = URL(fileURLWithPath: node.name).pathExtension.lowercased()
        // Files without an extension are likely text (Makefile, Dockerfile, etc.)
        return ext.isEmpty || Self.textExtensions.contains(ext)
    }

    private func openFile() {
        if let status = node.gitStatus {
            let untracked = status == .untracked
            onOpenFile?(node.relativePath, .diff(staged: node.isGitStaged, untracked: untracked))
        } else if isTextFile {
            onOpenFile?(node.relativePath, .edit)
        } else {
            onOpenFile?(node.relativePath, .preview)
        }
    }
}
