import SwiftUI

/// Persistent bottom-edge banner shown when a high-risk agent operation is detected.
/// Non-blocking: does not cover other sessions or prevent navigation.
/// Not auto-dismissing — the user must tap "Stop Agent" or "Allow".
struct RiskAlertBannerView: View {
    let alert: RiskAlert
    /// Sends Ctrl+C to the terminal then dismisses the banner.
    let onStopAgent: () -> Void
    /// Dismisses the banner and allows the operation to continue.
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: AppUI.Spacing.lg) {
            severityIcon
            VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                Text(alert.description)
                    .font(AppUI.Font.bodyMedium)
                    .foregroundStyle(.primary)
                Text(alert.commandSnippet)
                    .font(AppUI.Font.labelMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            actionButtons
        }
        .padding(.horizontal, AppUI.Spacing.xl)
        .padding(.vertical, AppUI.Spacing.md)
        .background(.regularMaterial)
        .overlay(alignment: .top) { severityAccentLine }
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Spacing.md))
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.bottom, AppUI.Spacing.xxl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var severityIcon: some View {
        Image(systemName: alert.severity == .critical
            ? "exclamationmark.triangle.fill"
            : "exclamationmark.circle.fill")
            .font(AppUI.Font.title2)
            .foregroundColor(alert.severity == .critical ? .red : .orange)
    }

    private var severityAccentLine: some View {
        Rectangle()
            .fill(alert.severity == .critical ? Color.red : Color.orange)
            .frame(height: 2)
    }

    private var actionButtons: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Button("Stop Agent", role: .destructive, action: onStopAgent)
                .keyboardShortcut(.cancelAction)
            Button("Allow", action: onAllow)
                .keyboardShortcut(.defaultAction)
        }
    }
}
