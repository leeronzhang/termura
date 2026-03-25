import SwiftUI

// MARK: - Project Tab

extension SidebarView {
    @ViewBuilder
    var projectContent: some View {
        let root = sessionStore.projectRoot.isEmpty
            ? activeSessionWorkingDirectory
            : sessionStore.projectRoot
        if let service = gitService, !root.isEmpty {
            SidebarProjectContent(
                gitService: service,
                projectRoot: root,
                onOpenFile: onOpenFile
            )
        } else {
            sidebarEmptyState(icon: "folder", message: "No project open")
        }
    }
}

/// Project file tree with integrated git status.
struct SidebarProjectContent: View {
    @StateObject private var viewModel: ProjectViewModel
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    init(
        gitService: any GitServiceProtocol,
        projectRoot: String,
        onOpenFile: ((String, FileOpenMode) -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: ProjectViewModel(gitService: gitService, projectRoot: projectRoot)
        )
        self.onOpenFile = onOpenFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if viewModel.gitResult.isGitRepo {
                branchBar
                Divider().padding(.horizontal, AppUI.Spacing.xxxl)
            }
            fileTree
        }
        .task { viewModel.refresh() }
        .onDisappear { viewModel.tearDown() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Project")
                .panelHeaderStyle()
            Spacer()
            ProgressView()
                .scaleEffect(0.6)
                .opacity(viewModel.isLoading ? 1 : 0)
            Button { viewModel.refresh() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    // MARK: - Branch

    private var branchBar: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "arrow.triangle.branch")
                .font(AppUI.Font.label)
                .foregroundColor(.accentColor)
            Text(viewModel.gitResult.branch)
                .font(AppUI.Font.labelMono)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.md)
    }

    // MARK: - File Tree

    @ViewBuilder
    private var fileTree: some View {
        if viewModel.tree.isEmpty && !viewModel.isLoading {
            sidebarEmpty
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.tree) { node in
                        FileTreeRowView(
                            node: node,
                            depth: 0,
                            onOpenFile: onOpenFile
                        )
                    }
                }
            }
        }
    }

    private var sidebarEmpty: some View {
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
}

// MARK: - File Tree Row

private struct FileTreeRowView: View {
    let node: FileTreeNode
    let depth: Int
    var onOpenFile: ((String, FileOpenMode) -> Void)?
    @State private var isExpanded = false

    /// Auto-expand root level on first appear.
    init(node: FileTreeNode, depth: Int, onOpenFile: ((String, FileOpenMode) -> Void)? = nil) {
        self.node = node
        self.depth = depth
        self.onOpenFile = onOpenFile
        _isExpanded = State(initialValue: depth == 0 && node.isDirectory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
            if node.isDirectory && isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeRowView(
                        node: child,
                        depth: depth + 1,
                        onOpenFile: onOpenFile
                    )
                }
            }
        }
    }

    private var rowContent: some View {
        Button {
            if node.isDirectory {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } else {
                openFile()
            }
        } label: {
            HStack(spacing: AppUI.Spacing.sm) {
                // Indentation
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth) * 16)
                }

                // Folder chevron or file icon
                if node.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(AppUI.Font.label)
                        .foregroundColor(directoryColor)
                } else {
                    Spacer().frame(width: 12)
                    Image(systemName: "doc")
                        .font(AppUI.Font.label)
                        .foregroundColor(fileColor)
                }

                Text(node.name)
                    .font(AppUI.Font.labelMono)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Git status indicator
                if let status = node.gitStatus, !node.isDirectory {
                    gitBadge(status, staged: node.isGitStaged)
                }
            }
            .padding(.horizontal, AppUI.Spacing.xxxl)
            .padding(.vertical, AppUI.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Colors

    private var directoryColor: Color {
        node.gitStatus != nil ? .orange : .secondary
    }

    private var fileColor: Color {
        guard let status = node.gitStatus else { return .secondary }
        switch status {
        case .added: return .green
        case .deleted: return .red
        case .untracked: return .secondary
        default: return node.isGitStaged ? .green : .orange
        }
    }

    // MARK: - Git badge

    @ViewBuilder
    private func gitBadge(_ kind: GitFileStatus.Kind, staged: Bool) -> some View {
        switch kind {
        case .modified:
            Text("M")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(staged ? .green : .orange)
        case .added:
            Text("A")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
        case .deleted:
            Text("D")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
        case .untracked:
            Text("U")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
        case .renamed, .copied:
            Text("R")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.blue)
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
