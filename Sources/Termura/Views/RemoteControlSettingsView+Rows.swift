import SwiftUI
import TermuraRemoteProtocol

/// Row-rendering helpers for `RemoteControlSettingsView`. Pulled into
/// their own file so the main view stays under §6.1's 250-line soft cap.
extension RemoteControlSettingsView {
    func deviceRow(_ device: PairedDeviceSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.nickname).font(.body)
                    if !device.isActive {
                        Text("revoked")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .cornerRadius(4)
                    }
                }
                Text("Paired \(device.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if device.isActive {
                Button("Revoke", role: .destructive) {
                    pendingRevokeId = device.id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(controller.isWorking)
            }
        }
    }

    func auditRow(_ entry: RemoteAuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.line)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                outcomeBadge(entry.outcome)
            }
            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func outcomeBadge(_ outcome: RemoteAuditOutcome) -> some View {
        switch outcome {
        case .dispatched:
            Label("dispatched", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
                .help("Dispatched")
        case .awaitingConfirmation:
            Label("awaiting", systemImage: "hourglass")
                .labelStyle(.iconOnly)
                .foregroundStyle(.orange)
                .help("Awaiting confirmation")
        case let .rejected(reason):
            Label(reason, systemImage: "xmark.octagon.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
                .help("Rejected: \(reason)")
        }
    }
}
