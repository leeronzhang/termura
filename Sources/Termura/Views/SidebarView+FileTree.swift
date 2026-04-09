import SwiftUI

extension SidebarProjectContent {
    // MARK: - Row 4+: File Tree

    @ViewBuilder
    var fileTree: some View {
        if viewModel.tree.isEmpty && !viewModel.isLoading {
            sidebarEmpty
        } else {
            List(viewModel.flatVisibleItems, selection: $selectedItemID) { item in
                FileTreeRowView(
                    node: item.node,
                    depth: item.depth,
                    isExpanded: viewModel.expandedNodeIDs.contains(item.node.id),
                    isActive: isFileActive(item.node),
                    onTap: {}
                )
                .tag(item.id)
                .listRowInsets(EdgeInsets(
                    top: 0, leading: AppUI.Spacing.lg,
                    bottom: 0, trailing: 0
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: selectedItemID) { _, newValue in
                guard let id = newValue else { return }
                // Clear selection immediately so the same row can be tapped again
                selectedItemID = nil
                handleItemTap(id: id)
            }
        }
    }

    func handleItemTap(id: String) {
        guard let item = viewModel.flatVisibleItems.first(where: { $0.id == id }) else {
            return
        }
        if item.node.isDirectory {
            viewModel.toggleExpand(item.node)
        } else {
            openFile(item.node)
        }
    }

    func isFileActive(_ node: FileTreeNode) -> Bool {
        guard let active = activeFilePath, !node.isDirectory else { return false }
        return node.relativePath == active
    }

    func openFile(_ node: FileTreeNode) {
        if let status = node.gitStatus {
            let untracked = status == .untracked
            onOpenFile?(node.relativePath, .diff(staged: node.isGitStaged, untracked: untracked))
        } else if isTextFile(node) {
            onOpenFile?(node.relativePath, .edit)
        } else {
            onOpenFile?(node.relativePath, .preview)
        }
    }

    static let textExtensions: Set<String> = [
        "swift", "m", "h", "c", "cpp", "rs", "go", "py", "rb", "js", "ts",
        "jsx", "tsx", "json", "yaml", "yml", "toml", "xml", "plist",
        "html", "css", "scss", "less", "sh", "bash", "zsh", "fish",
        "md", "markdown", "txt", "log", "env", "gitignore", "editorconfig",
        "lock", "resolved", "cfg", "ini", "conf", "sql", "graphql",
        "vue", "svelte", "astro", "r", "lua", "zig", "nim", "ex", "exs",
        "java", "kt", "scala", "dart", "php", "pl", "pm"
    ]

    func isTextFile(_ node: FileTreeNode) -> Bool {
        let ext = URL(fileURLWithPath: node.name).pathExtension.lowercased()
        return ext.isEmpty || Self.textExtensions.contains(ext)
    }

    var sidebarEmpty: some View {
        VStack(spacing: AppUI.Spacing.smMd) {
            Image(systemName: "folder")
                .font(AppUI.Font.hero)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
            Text("Empty directory")
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Git UI helpers

    func gitInlineStat(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppUI.Font.labelMono.weight(.semibold))
            .foregroundColor(color)
    }
}
