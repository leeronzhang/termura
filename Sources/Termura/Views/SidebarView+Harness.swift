import AppKit
import SwiftUI

// MARK: - Harness Tab

extension SidebarView {
    @ViewBuilder
    var harnessContent: some View {
        let projectRoot = activeSessionWorkingDirectory
        SidebarHarnessContent(
            repository: projectContext.ruleFileRepository,
            projectRoot: projectRoot,
            onOpenFile: onOpenFile
        )
    }

    var activeSessionWorkingDirectory: String {
        if let activeID = sessionStore.activeSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == activeID }) {
            let dir = session.workingDirectory
            if !dir.isEmpty { return dir }
        }
        return AppConfig.Paths.homeDirectory
    }
}

/// Harness content following the Agent tab structure: header → divider → content.
struct SidebarHarnessContent: View {
    @StateObject private var viewModel: HarnessViewModel
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    init(
        repository: any RuleFileRepositoryProtocol,
        projectRoot: String,
        onOpenFile: ((String, FileOpenMode) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: HarnessViewModel(repository: repository, projectRoot: projectRoot))
        self.onOpenFile = onOpenFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                fileList
                    .padding(.horizontal, AppUI.Spacing.lg)
                if !viewModel.corruptionResults.isEmpty {
                    corruptionSection
                }
            }
            footer
        }
        .task { await viewModel.loadRuleFiles() }
    }

    private var header: some View {
        HStack {
            Text("Harness")
                .panelHeaderStyle()
            Spacer()
            Button {
                Task { await viewModel.runCorruptionScan() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedFilePath == nil || viewModel.isScanning)
            .help("Scan for issues")
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private var fileList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.ruleFiles) { file in
                let isSelected = viewModel.selectedFilePath == file.filePath
                Button {
                    Task { await viewModel.selectFile(file.filePath) }
                    onOpenFile?(file.filePath, .edit)
                } label: {
                    HStack(spacing: AppUI.Spacing.md) {
                        FileTypeIcon.image(for: file.fileName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: AppUI.Size.fileTypeIcon, height: AppUI.Size.fileTypeIcon)
                            .foregroundColor(.secondary)
                        Text(file.fileName)
                            .font(isSelected ? AppUI.Font.title3Medium : AppUI.Font.body)
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("v\(file.version)")
                            .font(AppUI.Font.captionMono)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, AppUI.Spacing.lg)
                    .padding(.vertical, AppUI.Spacing.smMd)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(AppUI.Opacity.selected)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppUI.Radius.md)
                            .stroke(isSelected ? Color.accentColor.opacity(AppUI.Opacity.border) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var corruptionSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            Text("Issues (\(viewModel.corruptionResults.count))")
                .sectionLabelStyle()
                .foregroundColor(.orange)
                .padding(.horizontal, AppUI.Spacing.lg)
                .padding(.top, AppUI.Spacing.lg)

            ForEach(viewModel.corruptionResults) { result in
                HStack(spacing: AppUI.Spacing.md) {
                    Image(systemName: severityIcon(result.severity))
                        .foregroundColor(severityColor(result.severity))
                        .font(AppUI.Font.caption)
                    Text(result.message)
                        .font(AppUI.Font.label)
                        .lineLimit(2)
                }
                .padding(.horizontal, AppUI.Spacing.lg)
                .padding(.vertical, AppUI.Spacing.xs)
            }
        }
        .padding(.bottom, AppUI.Spacing.md)
    }

    private var footer: some View {
        HStack {
            Text("\(viewModel.ruleFiles.count) files")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.md)
    }

    private func severityIcon(_ severity: CorruptionSeverity) -> String {
        switch severity {
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func severityColor(_ severity: CorruptionSeverity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}

// MARK: - Recursive tree node

struct SidebarTreeNodeView: View {
    let node: SessionTreeNode
    let sessionStore: SessionStore
    let sessionRow: (SessionRecord, (() -> Void)?, Bool) -> AnyView

    @State private var isExpanded = true

    var body: some View {
        if !node.record.isPinned {
            sessionRow(
                node.record,
                node.hasChildren ? {
                    withAnimation(.easeOut(duration: AppUI.Animation.quick)) {
                        isExpanded.toggle()
                    }
                } : nil,
                isExpanded
            )
            .padding(.leading, CGFloat(node.depth) * BranchIndicatorView.indentPerLevel)
            .overlay(alignment: .leading) {
                if node.depth > 0 {
                    BranchIndicatorView(
                        depth: node.depth,
                        branchType: node.record.branchType,
                        hasChildren: node.hasChildren
                    )
                }
            }

            if isExpanded {
                ForEach(node.children) { child in
                    SidebarTreeNodeView(
                        node: child,
                        sessionStore: sessionStore,
                        sessionRow: sessionRow
                    )
                }
            }
        }
    }
}
