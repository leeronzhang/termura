import SwiftUI

/// Alert presented when a high-risk operation is detected.
/// Offers Proceed / Cancel options with risk severity indication.
struct InterventionAlertView: View {
    let alert: RiskAlert
    let onProceed: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: AppUI.Spacing.xl) {
            icon
            title
            description

            HStack(spacing: AppUI.Spacing.lg) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Proceed", role: .destructive, action: onProceed)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppUI.Spacing.xxxl)
        .frame(width: 340)
    }

    private var icon: some View {
        Image(systemName: alert.severity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
            .font(AppUI.Font.alertIcon)
            .foregroundColor(alert.severity == .critical ? .red : .orange)
    }

    private var title: some View {
        Text("High-Risk Operation Detected")
            .font(.headline)
    }

    private var description: some View {
        VStack(spacing: AppUI.Spacing.sm) {
            Text(alert.description)
                .font(.subheadline)
                .foregroundColor(.primary)
            Text("Severity: \(alert.severity.rawValue.uppercased())")
                .font(.caption)
                .foregroundColor(alert.severity == .critical ? .red : .orange)
        }
    }
}
