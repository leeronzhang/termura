import SwiftUI

// MARK: - Bottom git bar

// Single-row status bar that lives at the bottom of the Project tab in `.files`
// view-mode. Hosts: branch · remote indicator · change summary · ahead/behind
// stats · loading spinner · [Commit] CTA.
//
// Split out of SidebarView+Project.swift to keep that file at scannable size
// (CLAUDE.md §6.1 soft budget). All members are extension methods on
// `SidebarProjectContent`.

extension SidebarProjectContent {
    private var git: GitStatusResult { viewModel.gitResult }

    var bottomGitBar: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            Image(systemName: "arrow.triangle.branch")
                .font(AppUI.Font.caption)
                .foregroundColor(.primary)
            Text(git.branch)
                .font(AppUI.Font.labelMono)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            remoteIndicator
            if let summary = changeSummary {
                Text(summary)
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary)
            }
            if git.ahead > 0 {
                gitInlineStat("\u{2191}\(git.ahead)", color: .brandGreen)
            }
            if git.behind > 0 {
                gitInlineStat("\u{2193}\(git.behind)", color: .orange)
            }
            // Loading indicator: keeps a stable footprint via opacity toggle.
            ProgressView()
                .controlSize(.mini)
                .opacity(viewModel.isLoading ? 1 : 0)
            Spacer()
            if git.files.isEmpty == false {
                commitButton
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.xl)
    }

    // MARK: - Remote indicator

    /// Shows the configured remote host (or a dimmed "no remote" affordance).
    /// Click → opens the AI-delegated `RemoteSetupPopover`.
    var remoteIndicator: some View {
        let isConfigured = git.remoteURL != nil
        return Button {
            guard !projectScope.aiCommitService.isBusy else { return }
            showRemotePopover = true
        } label: {
            HStack(spacing: AppUI.Spacing.xxs) {
                Image(systemName: "arrow.up.forward.app")
                    .font(AppUI.Font.caption)
                Text(isConfigured ? (git.remoteHost ?? "remote") : "no remote")
                    .font(AppUI.Font.captionMono)
            }
            .foregroundColor(
                isConfigured
                    ? .secondary
                    : .secondary.opacity(AppUI.Opacity.dimmed)
            )
        }
        .buttonStyle(.plain)
        .help(remoteIndicatorTooltip)
        .disabled(projectScope.aiCommitService.isBusy)
        .accessibilityLabel(isConfigured ? "Configured remote" : "No remote configured")
        .accessibilityHint("Opens the AI remote setup panel")
        .popover(isPresented: $showRemotePopover, arrowEdge: .top) {
            RemoteSetupPopover(
                isPresented: $showRemotePopover,
                projectRoot: URL(fileURLWithPath: viewModel.projectRootPath),
                currentRemoteURL: git.remoteURL,
                currentRemoteHost: git.remoteHost
            )
        }
    }

    private var remoteIndicatorTooltip: String {
        if let url = git.remoteURL {
            return "Push remote: \(url) — click to change"
        }
        return "No remote configured — click to set one up with AI"
    }

    /// Pluralized "N change(s)" prefix; nil when working tree is clean.
    var changeSummary: String? {
        let count = git.files.count
        guard count > 0 else { return nil }
        return "\u{00B7} \(count) change\(count == 1 ? "" : "s")"
    }

    // MARK: - Commit button

    var commitButton: some View {
        Button {
            guard !projectScope.aiCommitService.isBusy else { return }
            showCommitPopover = true
        } label: {
            HStack(spacing: AppUI.Spacing.xs) {
                if projectScope.aiCommitService.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.brandGreen)
                }
                Text("Commit")
                    .font(AppUI.Font.captionMono.weight(.semibold))
                    .foregroundColor(.brandGreen)
            }
            .padding(.horizontal, AppUI.Spacing.md)
            .padding(.vertical, AppUI.Spacing.xs)
            .background(
                // 8pt radius matches the codebase convention for subtle rounded buttons
                // (AppUI.Radius.* are all 0pt — sharp by default; we opt in here).
                RoundedRectangle(cornerRadius: AppUI.Spacing.md)
                    .stroke(
                        Color.brandGreen.opacity(
                            projectScope.aiCommitService.isBusy ? AppUI.Opacity.dimmed : 1
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(projectScope.aiCommitService.isBusy)
        .popover(isPresented: $showCommitPopover, arrowEdge: .top) {
            CommitPopover(
                isPresented: $showCommitPopover,
                projectRoot: URL(fileURLWithPath: viewModel.projectRootPath)
            )
        }
        .help("Commit changes via AI")
        .accessibilityLabel("Commit changes")
    }
}
