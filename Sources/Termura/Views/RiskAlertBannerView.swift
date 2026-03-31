import AppKit
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
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Spacing.xs))
        .frame(maxWidth: AppConfig.Agent.bannerMaxWidth)
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
            .accessibilityHidden(true)
    }

    private var severityAccentLine: some View {
        Rectangle()
            .fill(alert.severity == .critical ? Color.red : Color.orange)
            .frame(height: 2)
            .accessibilityHidden(true)
    }

    private var actionButtons: some View {
        HStack(spacing: AppUI.Spacing.md) {
            stopAgentButton
            allowButton
        }
    }

    /// AppKitClickableOverlay is required — the terminal NSView (NSViewRepresentable) intercepts
    /// AppKit hitTest before SwiftUI gestures fire. Overlay an AppKit NSView so events are routed
    /// at the correct Z-order (same pattern as ComposerOverlayView's notesToggleButton/sendButton).
    private var stopAgentButton: some View {
        Text("Stop Agent")
            .font(AppUI.Font.bodyMedium)
            .foregroundStyle(.primary)
            .padding(.horizontal, AppUI.Spacing.md)
            .padding(.vertical, AppUI.Spacing.sm)
            .background(Color(nsColor: .controlColor), in: RoundedRectangle(cornerRadius: AppUI.Spacing.xs))
            .overlay(AppKitClickableOverlay(action: onStopAgent))
            .accessibilityLabel("Stop Agent")
            .accessibilityHint("Sends interrupt signal to the terminal")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { onStopAgent() }
    }

    private var allowButton: some View {
        Text("Allow")
            .font(AppUI.Font.bodyMedium)
            .foregroundStyle(.white)
            .padding(.horizontal, AppUI.Spacing.md)
            .padding(.vertical, AppUI.Spacing.sm)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: AppUI.Spacing.xs))
            .overlay(AppKitClickableOverlay(action: onAllow))
            .accessibilityLabel("Allow")
            .accessibilityHint("Allows the detected operation to continue")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { onAllow() }
    }
}

#if DEBUG
#Preview("Risk Alert Banner — Critical") {
    RiskAlertBannerView(
        alert: RiskAlert(
            trigger: "rm -rf",
            description: "Recursive force delete",
            severity: .critical,
            commandSnippet: "rm -rf /Users/dev/project/node_modules"
        ),
        onStopAgent: {},
        onAllow: {}
    )
    .frame(width: 700)
    .padding()
}

#Preview("Risk Alert Banner — High") {
    RiskAlertBannerView(
        alert: RiskAlert(
            trigger: "git reset --hard",
            description: "Hard reset (discards changes)",
            severity: .high,
            commandSnippet: "git reset --hard HEAD~5"
        ),
        onStopAgent: {},
        onAllow: {}
    )
    .frame(width: 700)
    .padding()
}
#endif
