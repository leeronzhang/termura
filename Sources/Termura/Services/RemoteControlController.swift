// Bridges the actor-isolated `RemoteIntegration` protocol to the SwiftUI
// settings layer. The controller exposes synchronous-readable, observable
// state — `isEnabled`, `latestInvitationJSON`, `lastError` — so the
// settings tab can drive a Toggle + invitation pasteboard without leaking
// actor concurrency into the view.
//
// PR10a addition: enabling the toggle now also installs the per-user
// LaunchAgent plist via `LaunchAgentInstaller`, and disabling removes it,
// so `~/Library/LaunchAgents/com.termura.remote-agent.plist` matches the
// in-app state on every transition.

import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteControlController")

@Observable
@MainActor
final class RemoteControlController {
    private(set) var isEnabled = false
    private(set) var isWorking = false
    private(set) var latestInvitationJSON: String?
    private(set) var lastError: String?
    private(set) var pairedDevices: [PairedDeviceSummary] = []
    private(set) var auditEntries: [RemoteAuditEntry] = []

    private let integration: any RemoteIntegration
    private let codec: any RemoteCodec
    private let installer: LaunchAgentInstaller
    private let plistConfig: LaunchAgentInstaller.PlistConfig

    init(
        integration: any RemoteIntegration,
        installer: LaunchAgentInstaller = LaunchAgentInstaller(),
        plistConfig: LaunchAgentInstaller.PlistConfig = .defaultRemoteAgent,
        codec: any RemoteCodec = JSONRemoteCodec()
    ) {
        self.integration = integration
        self.installer = installer
        self.plistConfig = plistConfig
        self.codec = codec
    }

    func enable() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await integration.start()
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to start remote integration: \(error.localizedDescription)")
            return
        }
        do {
            try await installer.install(plistConfig)
            isEnabled = true
            lastError = nil
            logger.info("Remote control enabled and LaunchAgent installed")
        } catch {
            lastError = "Server started but plist install failed: \(error.localizedDescription)"
            logger.error("Plist install failed; rolling back: \(error.localizedDescription)")
            await integration.stop()
        }
    }

    func disable() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await integration.stop()
        do {
            try await installer.uninstall(label: plistConfig.label)
        } catch {
            // Server is already stopped; surface the plist removal failure
            // but don't gate the disabled state on it (next enable will
            // reinstall via the idempotent path).
            lastError = "Server stopped but plist removal failed: \(error.localizedDescription)"
            logger.error("Plist removal failed: \(error.localizedDescription)")
        }
        isEnabled = false
        latestInvitationJSON = nil
        logger.info("Remote control disabled")
    }

    func generateInvitation() async {
        guard isEnabled, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let invitation = try await integration.issueInvitation()
            let data = try codec.encode(invitation)
            guard let json = String(data: data, encoding: .utf8) else {
                lastError = "Failed to render invitation"
                return
            }
            latestInvitationJSON = json
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to issue invitation: \(error.localizedDescription)")
        }
    }

    /// Reloads `pairedDevices` and `auditEntries` from the harness. Called
    /// from the settings view's `.task` modifier so the lists refresh each
    /// time the tab is opened.
    func refreshDevicesAndAudit() async {
        do {
            let devices = try await integration.listPairedDevices()
            pairedDevices = devices.sorted { $0.pairedAt > $1.pairedAt }
        } catch {
            logger.error("Failed to load paired devices: \(error.localizedDescription)")
        }
        do {
            let entries = try await integration.auditLog()
            auditEntries = entries
        } catch {
            logger.error("Failed to load audit log: \(error.localizedDescription)")
        }
    }

    /// Marks the device as revoked. Subsequent envelopes from that device id
    /// are rejected by the router. Refreshes the local list on success.
    func revokeDevice(id: UUID) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await integration.revokePairedDevice(id: id)
            await refreshDevicesAndAudit()
        } catch {
            lastError = "Revoke failed: \(error.localizedDescription)"
            logger.error("Revoke failed: \(error.localizedDescription)")
        }
    }
}

extension LaunchAgentInstaller.PlistConfig {
    /// Default config for the `com.termura.remote-agent` LaunchAgent. The
    /// executable path resolves to the helper bundled with Termura.app once
    /// PR10c wires the build phase; for now it points at a placeholder that
    /// is overridable via init for tests and dev installs.
    static let defaultRemoteAgent = LaunchAgentInstaller.PlistConfig(
        label: "com.termura.remote-agent",
        executablePath: "/Applications/Termura.app/Contents/Helpers/termura-remote-agent",
        runAtLoad: true
    )
}
