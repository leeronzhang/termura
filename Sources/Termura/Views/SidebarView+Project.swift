import OSLog
import SwiftUI

private let projectLogger = Logger(subsystem: "com.termura.app", category: "SidebarProject")

/// Inner navigation inside the Project sidebar tab.
enum ProjectViewMode: String, CaseIterable {
    case files
    case knowledge

    var label: String {
        switch self {
        case .files: "Project"
        case .knowledge: "Knowledge"
        }
    }
}

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
/// Hosts an inner view-mode toggle: Project (file tree + git) or Knowledge (`.termura/knowledge`).
/// Bottom git bar lives in `SidebarView+Project+GitBar.swift`.
struct SidebarProjectContent: View {
    @Environment(\.projectScope) var projectScope

    var viewModel: ProjectViewModel
    var activeFilePath: String?
    var onOpenFile: ((String, FileOpenMode) -> Void)?
    @State var viewMode: ProjectViewMode = .files
    @State var showCommitPopover = false
    @State var showRemotePopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Project / Knowledge tab toggle + project path
            projectRow
            switch viewMode {
            case .files:
                ProblemsSection(
                    diagnosticsStore: projectScope.diagnosticsStore,
                    onOpenFile: onOpenFile
                )
                fileTree
                if viewModel.gitResult.isGitRepo {
                    Divider()
                    bottomGitBar
                }
            case .knowledge:
                if let discovery = resolveDiscovery() {
                    SidebarKnowledgeContent(
                        discovery: discovery,
                        onOpenFile: onOpenFile
                    )
                } else {
                    knowledgeUnavailable
                }
            }
        }
        .task { viewModel.refresh() }
        .onDisappear { viewModel.tearDown() }
    }

    // MARK: - Knowledge resolution

    private func resolveDiscovery() -> ProjectDiscovery? {
        do {
            return try ProjectDiscovery(
                from: URL(fileURLWithPath: viewModel.projectRootPath)
            )
        } catch {
            // Non-critical: project may not have a `.termura/` directory yet.
            projectLogger.debug("Knowledge mode: no .termura at \(viewModel.projectRootPath): \(error.localizedDescription)")
            return nil
        }
    }

    private var knowledgeUnavailable: some View {
        VStack(spacing: AppUI.Spacing.smMd) {
            Image(systemName: "books.vertical")
                .font(AppUI.Font.hero)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
            Text("No knowledge directory")
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
            Text("Run a Termura command to create `.termura/`.")
                .font(AppUI.Font.micro)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppUI.Spacing.xxxl)
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

    // MARK: - Header: PROJECT / Knowledge inner-tab toggle + path

    private var projectRow: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
            HStack(spacing: AppUI.Spacing.lg) {
                viewModeButton(.files)
                viewModeButton(.knowledge)
                Spacer()
                if viewMode == .files && viewModel.gitResult.isGitRepo {
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

    private func viewModeButton(_ mode: ProjectViewMode) -> some View {
        let isActive = viewMode == mode
        return Button {
            viewMode = mode
        } label: {
            Text(mode.label)
                .font(AppUI.Font.panelHeader)
                .foregroundColor(isActive ? .primary : .secondary.opacity(AppUI.Opacity.dimmed))
                .textCase(.uppercase)
        }
        .buttonStyle(.plain)
        .help(mode.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
