import SwiftUI

// MARK: - Project Tab

extension SidebarView {
    @ViewBuilder
    var projectContent: some View {
        let root = sessionStore.projectRoot
            ?? activeSessionWorkingDirectory
        if !root.isEmpty {
            SidebarProjectContent(
                viewModel: projectScope.viewModel,
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
    @Environment(\.projectScope) private var projectScope

    var viewModel: ProjectViewModel
    var activeFilePath: String?
    var onOpenFile: ((String, FileOpenMode) -> Void)?
    @State var selectedItemID: String?

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
            // Problems section: appears when diagnostics are present
            ProblemsSection(
                diagnosticsStore: projectScope.diagnosticsStore,
                onOpenFile: onOpenFile
            )
            // Row 4+: file tree
            fileTree
        }
        .task { viewModel.refresh() }
        .onDisappear { viewModel.tearDown() }
    }

    // MARK: - Row 1: Git Host + Refresh

    private var gitHostRow: some View {
        HStack {
            Text(git.remoteHost ?? "Git")
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
            if let commit = git.lastCommit {
                let hash = String(commit.prefix(while: { $0 != " " }))
                Text(hash.prefix(8))
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
            }

            Spacer()

            // Right: ahead/behind + file stats (all inline, no pill backgrounds)
            HStack(spacing: AppUI.Spacing.mdLg) {
                if git.ahead > 0 {
                    gitInlineStat("\u{2191}\(git.ahead)", color: .accentColor)
                }
                if git.behind > 0 {
                    gitInlineStat("\u{2193}\(git.behind)", color: .orange)
                }
                if git.stagedCount > 0 {
                    gitInlineStat("A\(git.stagedCount)", color: .green)
                }
                if git.modifiedCount > 0 {
                    gitInlineStat("M\(git.modifiedCount)", color: .orange)
                }
                if git.untrackedCount > 0 {
                    gitInlineStat("U\(git.untrackedCount)", color: .cyan)
                }
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.smMd)
    }

    // MARK: - Row 3: PROJECT header + ignore toggle

    private var projectRow: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
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
                } else if git.isGitRepo {
                    Button {
                        viewModel.hideIgnoredFiles.toggle()
                    } label: {
                        Text(".gitignore")
                            .font(AppUI.Font.captionMono)
                            .foregroundColor(
                                viewModel.hideIgnoredFiles
                                    ? .primary
                                    : .secondary.opacity(AppUI.Opacity.dimmed)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(
                        viewModel.hideIgnoredFiles
                            ? "Showing tracked files only \u{2014} click to show all"
                            : "Showing all files \u{2014} click to hide ignored"
                    )
                }
            }
            Text(viewModel.displayPath)
                .font(AppUI.Font.captionMono)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
                .lineLimit(1)
                .truncationMode(.head)
                .help(viewModel.projectRootPath)
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.top, AppUI.Spacing.xxxl)
        .padding(.bottom, AppUI.Spacing.xs)
    }
}
