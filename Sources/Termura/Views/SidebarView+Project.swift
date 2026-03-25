import SwiftUI

// MARK: - Project Tab

extension SidebarView {
    @ViewBuilder
    var projectContent: some View {
        let root = sessionStore.projectRoot.isEmpty
            ? activeSessionWorkingDirectory
            : sessionStore.projectRoot
        if !root.isEmpty {
            SidebarProjectContent(
                gitService: projectContext.gitService,
                projectRoot: root,
                commandRouter: commandRouter,
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
        commandRouter: CommandRouter? = nil,
        onOpenFile: ((String, FileOpenMode) -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: ProjectViewModel(
                gitService: gitService,
                projectRoot: projectRoot,
                commandRouter: commandRouter
            )
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
            if !viewModel.gitResult.files.isEmpty {
                Text("\(viewModel.gitResult.files.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
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
                            expandedIDs: $viewModel.expandedNodeIDs,
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
