// PR9 Step 7 — Settings danger-zone surface for `revokeAll` and
// `resetPairings`. Pinned in its own file so the main settings view
// stays under the file-size soft cap and so the destructive UI stays
// visually grouped (its own Form section + a dedicated reset
// confirmation sheet).
//
// Plan §4.3 confirmation matrix:
//   * `revokeAll`     — single destructive `.alert` confirmation
//   * `resetPairings` — modal sheet with an explicit "I understand"
//                        Toggle gating the Reset button. macOS `.alert`
//                        cannot host a Toggle, so a sheet is the
//                        idiomatic way to render the double-confirm
//                        the plan calls for.

import SwiftUI

extension RemoteControlSettingsView {
    @ViewBuilder
    var dangerZoneSection: some View {
        Section {
            revokeAllRow
            resetPairingsRow
        } header: {
            Text("Danger zone")
        } footer: {
            Text(
                "Revoke marks every paired iPhone as inactive but keeps remote " +
                    "control running and the pair-keys retained — invite a fresh " +
                    "device to resume. Reset additionally wipes the pair-key store " +
                    "and asks the agent to clear its cursor and quarantine; remote " +
                    "control is disabled and re-enabling requires a fresh invitation."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var activeDeviceCount: Int {
        controller.pairedDevices.count(where: \.isActive)
    }

    @ViewBuilder
    private var revokeAllRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Revoke all devices")
                    .font(.body)
                Text(activeDeviceCount > 0
                    ? "Marks the \(activeDeviceCount) active device(s) as revoked. Remote control stays enabled."
                    : "No active devices — nothing to revoke.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revoke all", role: .destructive) {
                showRevokeAllConfirm = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(controller.isWorking || activeDeviceCount == 0)
        }
    }

    @ViewBuilder
    private var resetPairingsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reset all pairings")
                    .font(.body)
                Text("Wipes paired devices, pair keys, and agent state. Remote control will be disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset…", role: .destructive) {
                resetUnderstood = false
                showResetSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(controller.isWorking)
        }
    }

    @ViewBuilder
    var resetConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.lg) {
            Text("Reset all pairings?")
                .font(.title2.bold())
            Text("This will permanently:")
                .font(.body)
            VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                bulletRow("Sign out every paired iPhone (\(controller.pairedDevices.count) record(s)).")
                bulletRow("Delete every pair key from this Mac's keychain.")
                bulletRow("Ask the LaunchAgent to wipe its cursor and quarantine state.")
            }
            Toggle(isOn: $resetUnderstood) {
                Text("I understand this requires re-pairing every device.")
            }
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel") {
                    showResetSheet = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Reset", role: .destructive) {
                    showResetSheet = false
                    Task { await controller.resetPairings() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(!resetUnderstood || controller.isWorking)
            }
        }
        .padding(AppUI.Spacing.xxl)
        .frame(minWidth: 420)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AppUI.Spacing.sm) {
            Text("•").foregroundStyle(.secondary)
            Text(text)
        }
    }
}
