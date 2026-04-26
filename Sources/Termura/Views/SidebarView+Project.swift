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
/// Bottom git bar lives in `SidebarView+Project+GitBar.swift`.
struct SidebarProjectContent: View {
    @Environment(\.projectScope) var projectScope

    var viewModel: ProjectViewModel
    var activeFilePath: String?
    var onOpenFile: ((String, FileOpenMode) -> Void)?
    @State var showCommitPopover = false
    @State var showRemotePopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectRow
            ProblemsSection(
                diagnosticsStore: projectScope.diagnosticsStore,
                onOpenFile: onOpenFile
            )
            fileTree
            if viewModel.gitResult.isGitRepo {
                Divider()
                bottomGitBar
            }
        }
        .task { viewModel.refresh() }
        .onDisappear { viewModel.tearDown() }
    }

    // MARK: - .gitignore toggle (lives in the PROJECT header)

    private var gitignoreToggle: some View {
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

    // MARK: - Header: PROJECT label + path

    private var projectRow: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
            HStack(spacing: AppUI.Spacing.lg) {
                Text("Project")
                    .font(AppUI.Font.panelHeader)
                    .foregroundColor(.primary)
                    .textCase(.uppercase)
                Spacer()
                if viewModel.gitResult.isGitRepo {
                    gitignoreToggle
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
