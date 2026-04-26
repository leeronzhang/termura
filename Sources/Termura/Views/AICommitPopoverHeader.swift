import SwiftUI

/// Shared header used by `CommitPopover` and `RemoteSetupPopover`.
/// Shows either "Using <agent> · from <session>" when a headless-capable
/// agent is detected, or a warning if none is available.
struct AICommitPopoverHeader: View {
    let agent: AgentType?
    let sessionLabel: String?

    var body: some View {
        if let agent {
            HStack(spacing: AppUI.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(AppUI.Font.label)
                    .foregroundColor(.brandGreen)
                Text("Using \(agent.displayName)")
                    .font(AppUI.Font.bodyMedium)
                if let sessionLabel {
                    Text("· from \(sessionLabel)")
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, AppUI.Spacing.lg)
            .padding(.vertical, AppUI.Spacing.md)
        } else {
            HStack(alignment: .top, spacing: AppUI.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                    Text("No CLI agent detected")
                        .font(AppUI.Font.bodyMedium)
                    Text("Start `claude` or `codex` in a session, then try again.")
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, AppUI.Spacing.lg)
            .padding(.vertical, AppUI.Spacing.md)
        }
    }
}
