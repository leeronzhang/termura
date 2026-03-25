import SwiftUI

/// Sheet displayed when an agent's context window usage crosses a warning threshold.
struct ContextWindowAlertView: View {
    let alert: ContextWindowAlert
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: AppUI.Spacing.lgXl) {
            icon
            titleText
            TokenProgressView(
                estimatedTokens: alert.estimatedTokens,
                contextLimit: alert.contextLimit
            )
            .frame(maxWidth: 240)
            descriptionText
            dismissButton
        }
        .padding(AppUI.Spacing.xxl)
        .frame(width: 320)
    }

    // MARK: - Subviews

    private var icon: some View {
        Image(systemName: alert.level == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
            .font(AppUI.Font.alertIcon)
            .foregroundColor(alert.level == .critical ? .red : .orange)
    }

    private var titleText: some View {
        Text(alert.level == .critical ? "Context Nearly Full" : "Context Getting Full")
            .font(AppUI.Font.title3Medium)
    }

    private var descriptionText: some View {
        let msg = "\(alert.agentType.rawValue) has used \(percentageText) of its context window "
            + "(\(formattedLimit) tokens). Consider starting a new session to avoid degraded performance."
        return Text(msg)
            .font(AppUI.Font.label)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }

    private var dismissButton: some View {
        Button("Dismiss", action: onDismiss)
            .keyboardShortcut(.defaultAction)
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
