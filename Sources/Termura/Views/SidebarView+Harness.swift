import AppKit
import SwiftUI

// MARK: - Harness Tab

extension SidebarView {
    @ViewBuilder
    var harnessContent: some View {
        #if HARNESS_ENABLED
        let projectRoot = activeSessionWorkingDirectory
        SidebarHarnessContent(
            repository: dataScope.ruleFileRepository,
            projectRoot: projectRoot,
            activeContentTab: activeContentTab,
            onOpenFile: onOpenFile
        )
        #else
        HarnessUpsellView()
        #endif
    }

    var activeSessionWorkingDirectory: String {
        if let activeID = sessionStore.activeSessionID,
           let dir = sessionStore.session(id: activeID)?.workingDirectory {
            return dir
        }
        return AppConfig.Paths.homeDirectory
    }
}

/// Harness content following the Agent tab structure: header → divider → content.
struct SidebarHarnessContent: View {
    @StateObject private var viewModel: HarnessViewModel
    var activeContentTab: ContentTab?
    var onOpenFile: ((String, FileOpenMode) -> Void)?
    init(
        repository: any RuleFileRepositoryProtocol,
        projectRoot: String,
        activeContentTab: ContentTab? = nil,
        onOpenFile: ((String, FileOpenMode) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: HarnessViewModel(repository: repository, projectRoot: projectRoot))
        self.activeContentTab = activeContentTab
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
                    || activeContentTab?.filePath == file.filePath
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

// MARK: - Free-build upsell

/// Shown in place of real harness content when HARNESS_ENABLED is not set.
/// Explains the feature and links to the product page.
#if !HARNESS_ENABLED
struct HarnessUpsellView: View {
    private struct Feature {
        let icon: String
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        Feature(
            icon: "doc.text.magnifyingglass",
            title: "Rule File Management",
            detail: "Browse and version-track AGENTS.md and CLAUDE.md across all your projects."
        ),
        Feature(
            icon: "sparkle.magnifyingglass",
            title: "Corruption Detection",
            detail: "Scan rule files for structural issues and conflicting directives before they mislead your AI agent."
        ),
        Feature(
            icon: "wand.and.sparkles",
            title: "Experience Codification",
            detail: "Turn agent errors and successful patterns into durable rules with one click."
        ),
        Feature(
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            title: "Version History",
            detail: "See every change to a rule file, diff between versions, and roll back instantly."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppUI.Spacing.xl) {
                    tagline
                    featureList
                    ctaButton
                }
                .padding(.horizontal, AppUI.Spacing.xxxl)
                .padding(.vertical, AppUI.Spacing.xl)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Harness")
                .panelHeaderStyle()
            Spacer()
            Text("PRO")
                .font(AppUI.Font.captionMono)
                .foregroundColor(.white)
                .padding(.horizontal, AppUI.Spacing.smMd)
                .padding(.vertical, 2)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.sm))
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private var tagline: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            Text("Keep your AI agents on track.")
                .font(AppUI.Font.title3Medium)
                .foregroundColor(.primary)
            Text("Harness turns hard-won prompt engineering into permanent, versioned rules — so every agent session starts smarter.")
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.lg) {
            ForEach(features, id: \.title) { feature in
                HStack(alignment: .top, spacing: AppUI.Spacing.mdLg) {
                    Image(systemName: feature.icon)
                        .font(AppUI.Font.body)
                        .foregroundColor(.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                        Text(feature.title)
                            .font(AppUI.Font.labelMedium)
                            .foregroundColor(.primary)
                        Text(feature.detail)
                            .font(AppUI.Font.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var ctaButton: some View {
        Button {
            guard let url = URL(string: AppConfig.URLs.harnessProduct) else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack {
                Spacer()
                Text("Learn More & Upgrade")
                    .font(AppUI.Font.labelMedium)
                Image(systemName: "arrow.up.right")
                    .font(AppUI.Font.caption)
                Spacer()
            }
            .padding(.vertical, AppUI.Spacing.smMd)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
        }
        .buttonStyle(.plain)
    }
}
#endif
