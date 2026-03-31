import SwiftUI

/// Non-blocking bottom-edge banner shown when an agent's context window usage crosses a warning threshold.
struct ContextWindowAlertView: View {
    let alert: ContextWindowAlert
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: AppUI.Spacing.lg) {
            icon
            VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                Text(alert.level == .critical ? "Context Nearly Full" : "Context Getting Full")
                    .font(AppUI.Font.bodyMedium)
                    .foregroundStyle(.primary)
                Text(descriptionMessage)
                    .font(AppUI.Font.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            dismissButton
        }
        .padding(.horizontal, AppUI.Spacing.xl)
        .padding(.vertical, AppUI.Spacing.md)
        .background(.regularMaterial)
        .overlay(alignment: .top) { accentLine }
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Spacing.xs))
        .frame(maxWidth: AppConfig.Agent.bannerMaxWidth)
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.bottom, AppUI.Spacing.xxl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Subviews

    private var icon: some View {
        Image(systemName: alert.level == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
            .font(AppUI.Font.title2)
            .foregroundColor(alert.level == .critical ? .red : .orange)
            .accessibilityHidden(true)
    }

    private var accentLine: some View {
        Rectangle()
            .fill(alert.level == .critical ? Color.red : Color.orange)
            .frame(height: 2)
            .accessibilityHidden(true)
    }

    private var dismissButton: some View {
        Text("Dismiss")
            .font(AppUI.Font.bodyMedium)
            .foregroundStyle(.primary)
            .padding(.horizontal, AppUI.Spacing.md)
            .padding(.vertical, AppUI.Spacing.sm)
            .background(Color(nsColor: .controlColor), in: RoundedRectangle(cornerRadius: AppUI.Spacing.xs))
            .overlay(AppKitClickableOverlay(action: onDismiss))
            .accessibilityLabel("Dismiss")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { onDismiss() }
    }

    private var descriptionMessage: String {
        "\(alert.agentType.rawValue) has used \(percentageText) of its context window (\(formattedLimit) tokens)"
    }

    // MARK: - Formatting

    private var percentageText: String {
        String(format: "%.0f%%", alert.usageFraction * 100)
    }

    private var formattedLimit: String {
        alert.contextLimit >= 1000
            ? String(format: "%.0fk", Double(alert.contextLimit) / 1000)
            : "\(alert.contextLimit)"
    }
}

#if DEBUG
#Preview("Context Window Alert — Warning") {
    ContextWindowAlertView(
        alert: ContextWindowAlert(
            sessionID: SessionID(),
            agentType: .claudeCode,
            level: .warning,
            usageFraction: 0.82,
            estimatedTokens: 164_000,
            contextLimit: 200_000
        ),
        onDismiss: {}
    )
}

#Preview("Context Window Alert — Critical") {
    ContextWindowAlertView(
        alert: ContextWindowAlert(
            sessionID: SessionID(),
            agentType: .gemini,
            level: .critical,
            usageFraction: 0.96,
            estimatedTokens: 960_000,
            contextLimit: 1_000_000
        ),
        onDismiss: {}
    )
}
#endif
