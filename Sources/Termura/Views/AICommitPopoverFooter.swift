import SwiftUI

/// Shared footer for `CommitPopover` and `RemoteSetupPopover`.
/// Cancel = transparent capsule with secondary stroke; primary = brandGreen-filled
/// capsule. Both keyboard-accessible (esc / cmd+return).
struct AICommitPopoverFooter: View {
    let primaryLabel: String
    let primaryEnabled: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Spacer()
            Button(action: onCancel) {
                Text("Cancel")
                    .font(AppUI.Font.label)
                    .foregroundColor(.primary)
                    .padding(.horizontal, AppUI.Spacing.xl)
                    .padding(.vertical, AppUI.Spacing.smMd)
                    .background(
                        Capsule()
                            .stroke(Color.secondary.opacity(AppUI.Opacity.border), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)

            Button(action: onPrimary) {
                Text(primaryLabel)
                    .font(AppUI.Font.label.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppUI.Spacing.xl)
                    .padding(.vertical, AppUI.Spacing.smMd)
                    .background(
                        Capsule()
                            .fill(Color.brandGreen.opacity(primaryEnabled ? 1 : AppUI.Opacity.dimmed))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
    }
}
