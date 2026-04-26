import SwiftUI

/// Shared header used by `CommitPopover` and `RemoteSetupPopover`.
/// Shows either "Using <agent> · from <session>" when a headless-capable
/// agent is detected, or a warning when none is available.
///
/// The header text starts at the same leading edge (`AppUI.Spacing.lg`) as
/// the section labels below, so all popover content shares one visual baseline.
struct AICommitPopoverHeader: View {
    let agent: AgentType?
    let sessionLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
            if let agent {
                HStack(spacing: AppUI.Spacing.xs) {
                    Text("Using \(agent.displayName)")
                        .font(AppUI.Font.bodyMedium)
                        .foregroundColor(.brandGreen)
                    if let sessionLabel {
                        Text("· from \(sessionLabel)")
                            .font(AppUI.Font.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No CLI agent detected")
                    .font(AppUI.Font.bodyMedium)
                    .foregroundColor(.orange)
                Text("Start `claude` or `codex` in a session, then try again.")
                    .font(AppUI.Font.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
    }
}
