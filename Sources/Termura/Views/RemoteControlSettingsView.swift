import AppKit
import SwiftUI
import TermuraRemoteProtocol

struct RemoteControlSettingsView: View {
    @Bindable var controller: RemoteControlController
    @State var pendingRevokeId: UUID?
    @State var showRevokeAllConfirm = false
    @State var showResetSheet = false
    @State var resetUnderstood = false

    var body: some View {
        Form {
            statusSection
            pairingSection
            devicesSection
            dangerZoneSection
            auditSection
        }
        .formStyle(.grouped)
        .padding(AppUI.Spacing.xxl)
        .task { await controller.refreshDevicesAndAudit() }
        .alert(
            "Revoke this device?",
            isPresented: revokeAlertBinding,
            presenting: pendingRevokeId
        ) { id in
            Button("Revoke", role: .destructive) {
                Task { await controller.revokeDevice(id: id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Revoked devices can't send new commands. They'll need to pair again to reconnect.")
        }
        .alert(
            "Revoke all paired devices?",
            isPresented: $showRevokeAllConfirm
        ) {
            Button("Revoke all", role: .destructive) {
                Task { await controller.revokeAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Every paired iPhone will be marked as inactive. " +
                    "Remote control stays enabled and pair keys are kept, " +
                    "so re-inviting a device skips the full pairing flow."
            )
        }
        .sheet(isPresented: $showResetSheet) {
            resetConfirmationSheet
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            Toggle(isOn: enableBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable remote control")
                    Text("Lets a paired iPhone send commands and receive output snapshots from this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(controller.isWorking)
            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Status")
        }
    }

    private var pairingSection: some View {
        Section {
            if controller.isEnabled {
                Button {
                    Task { await controller.generateInvitation() }
                } label: {
                    Label("Generate invitation", systemImage: "qrcode")
                }
                .disabled(controller.isWorking)
                if let json = controller.latestInvitationJSON {
                    invitationBlock(json: json)
                }
            } else {
                Text("Enable remote control to generate a pairing invitation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Pairing")
        } footer: {
            Text("Open Termura Remote on your iPhone and paste this JSON to pair. "
                + "Each invitation can only be used once and expires after 5 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var devicesSection: some View {
        Section {
            if controller.pairedDevices.isEmpty {
                Text("No paired devices yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.pairedDevices) { device in
                    deviceRow(device)
                }
            }
        } header: {
            Text("Paired devices")
        }
    }

    private var auditSection: some View {
        Section {
            if controller.auditEntries.isEmpty {
                Text("No commands recorded yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.auditEntries.prefix(50)) { entry in
                    auditRow(entry)
                }
            }
        } header: {
            Text("Recent commands")
        } footer: {
            Text("Last 50 commands shown. Stored locally in ~/Library/Application Support/Termura.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rows

    private func deviceRow(_ device: PairedDeviceSummary) -> some View {
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

    private func auditRow(_ entry: RemoteAuditEntry) -> some View {
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
    private func outcomeBadge(_ outcome: RemoteAuditOutcome) -> some View {
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

    // MARK: - Bindings

    private var enableBinding: Binding<Bool> {
        Binding(
            get: { controller.isEnabled },
            set: { newValue in
                Task {
                    if newValue {
                        await controller.enable()
                    } else {
                        await controller.disable()
                    }
                }
            }
        )
    }

    private var revokeAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingRevokeId != nil },
            set: { presenting in
                if !presenting { pendingRevokeId = nil }
            }
        )
    }

    private func invitationBlock(json: String) -> some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            ScrollView {
                Text(json)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppUI.Spacing.sm)
            }
            .frame(minHeight: 80, maxHeight: 160)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            Button("Copy to clipboard") { copyToClipboard(json) }
                .buttonStyle(.bordered)
        }
    }

    private func copyToClipboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
