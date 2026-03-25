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
                viewModel: projectContext.projectViewModel,
                activeFilePath: activeContentTab?.filePath,
                onOpenFile: onOpenFile
            )
        } else {
            sidebarEmptyState(icon: "folder", message: "No project open")
        }
    }
}

/// Project file tree with integrated git status.
struct SidebarProjectContent: View {
    @ObservedObject var viewModel: ProjectViewModel
    var activeFilePath: String?
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    private var git: GitStatusResult { viewModel.gitResult }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Git host label (left) + loading/refresh (right)
            if git.isGitRepo {
                gitHostRow
                // Row 2: branch / commit hash (left) + stats (right)
                branchRow
            }
            // Row 3: PROJECT label (left) + path (right)
            projectRow
            // Row 4+: file tree
            fileTree
        }
        .task { viewModel.refresh() }
        .onDisappear { viewModel.tearDown() }
    }

    // MARK: - Row 1: Git Host + Refresh

    private var gitHostRow: some View {
        HStack {
            Text(git.remoteHost.isEmpty ? "Git" : git.remoteHost)
                .panelHeaderStyle()
            Spacer()
            ProgressView()
                .controlSize(.mini)
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

    // MARK: - Row 2: Branch / Commit + Stats

    private var branchRow: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            // Left: branch name + short hash
            Image(systemName: "arrow.triangle.branch")
                .font(AppUI.Font.caption)
                .foregroundColor(.primary)
            Text(git.branch)
                .font(AppUI.Font.labelMono)
                .foregroundColor(.primary)
                .lineLimit(1)
            if !git.lastCommit.isEmpty {
                let hash = String(git.lastCommit.prefix(while: { $0 != " " }))
                Text(hash.prefix(8))
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
            }

            Spacer()

            // Right: ahead/behind + file stats
            if git.ahead > 0 {
                gitMiniPill("\u{2191}\(git.ahead)", color: .accentColor)
            }
            if git.behind > 0 {
                gitMiniPill("\u{2193}\(git.behind)", color: .orange)
            }
            if git.stagedCount > 0 {
                gitInlineStat("+\(git.stagedCount)", color: .green)
            }
            if git.modifiedCount > 0 {
                gitInlineStat("~\(git.modifiedCount)", color: .orange)
            }
            if git.untrackedCount > 0 {
                gitInlineStat("?\(git.untrackedCount)", color: .secondary)
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.smMd)
    }

    // MARK: - Row 3: PROJECT + Path

    private var projectRow: some View {
        HStack {
            Text("Project")
                .panelHeaderStyle()
            Spacer()
            if !git.isGitRepo {
                ProgressView()
                    .controlSize(.mini)
                    .opacity(viewModel.isLoading ? 1 : 0)
                Button { viewModel.refresh() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(AppUI.Font.label)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text(viewModel.displayPath)
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(viewModel.projectRootPath)
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.top, AppUI.Spacing.xxxl)
        .padding(.bottom, AppUI.Spacing.xs)
    }

    // MARK: - Row 4+: File Tree

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
                            activeFilePath: activeFilePath,
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

    // MARK: - Git UI helpers

    private func gitMiniPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(AppUI.Opacity.strong))
            .clipShape(Capsule())
    }

    private func gitInlineStat(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.custom(AppConfig.Fonts.terminalFamily, size: 10).bold())
            .foregroundColor(color)
    }
}
