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
//
// PR9 Step 0: dependency-surface migration. The init now requires the
// agent bridge lifecycle handle and a `UserDefaultsStoring` so future
// PR9 steps can persist the on/off choice and tear the bridge down on
// disable. Step 0 only widens the surface — semantics of `enable` /
// `disable` / `generateInvitation` / `revokeDevice` are unchanged.

import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteControlController")

@Observable
@MainActor
final class RemoteControlController {
    // Read-only from the SwiftUI layer by convention; the actions
    // extension writes them as part of the disable / revokeAll /
    // resetPairings orchestration. Default `internal(set)` so the
    // cross-file extension can mutate them.
    var isEnabled = false
    var isWorking = false
    var latestInvitationJSON: String?
    var lastError: String?
    var pairedDevices: [PairedDeviceSummary] = []
    var auditEntries: [RemoteAuditEntry] = []

    let integration: any RemoteIntegration
    let agentBridge: any RemoteAgentBridgeLifecycle
    let userDefaults: any UserDefaultsStoring
    let codec: any RemoteCodec
    let installer: LaunchAgentInstaller
    let plistConfig: LaunchAgentInstaller.PlistConfig
    let clock: any AppClock
    let agentDeathProbe: any AgentDeathProbing
    let fallbackCleaner: any AgentKeychainFallbackCleaning

    init(
        integration: any RemoteIntegration,
        agentBridge: any RemoteAgentBridgeLifecycle,
        userDefaults: any UserDefaultsStoring,
        installer: LaunchAgentInstaller = LaunchAgentInstaller(),
        plistConfig: LaunchAgentInstaller.PlistConfig = .defaultRemoteAgent,
        codec: any RemoteCodec = JSONRemoteCodec(),
        clock: any AppClock = LiveClock(),
        agentDeathProbe: any AgentDeathProbing = AgentDeathProbe(),
        fallbackCleaner: any AgentKeychainFallbackCleaning = AgentKeychainFallbackCleaner()
    ) {
        self.integration = integration
        self.agentBridge = agentBridge
        self.userDefaults = userDefaults
        self.installer = installer
        self.plistConfig = plistConfig
        self.codec = codec
        self.clock = clock
        self.agentDeathProbe = agentDeathProbe
        self.fallbackCleaner = fallbackCleaner
        // Restore the user's last explicit on/off choice across relaunches.
        // Lazy: do NOT eagerly call `integration.start()` here — the actual
        // transport assembly stays deferred to the first explicit `enable`,
        // matching PR8 behaviour.
        isEnabled = userDefaults.bool(forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
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
            setEnabledFlag(true)
            lastError = nil
            logger.info("Remote control enabled and LaunchAgent installed")
        } catch {
            lastError = "Server started but plist install failed: \(error.localizedDescription)"
            logger.error("Plist install failed; rolling back: \(error.localizedDescription)")
            await integration.stop()
        }
    }

    /// Persists the on/off choice to `UserDefaults` and updates the
    /// observable in-memory mirror in lock-step. Idempotent. Used by
    /// `enable` (here) and the `disable` / `resetPairings` actions
    /// extension so a relaunch reflects the user's last explicit toggle.
    func setEnabledFlag(_ value: Bool) {
        isEnabled = value
        userDefaults.set(value, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
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
}

extension LaunchAgentInstaller.PlistConfig {
    /// Default config for the `com.termura.remote-agent` LaunchAgent. The
    /// executable path resolves to the helper bundled with Termura.app once
    /// PR10c wires the build phase; for now it points at a placeholder that
    /// is overridable via init for tests and dev installs.
    ///
    /// PR9 — `machServices` advertises the agent's bootstrap mach name to
    /// launchd. Without this, `NSXPCConnection(machServiceName:)` from the
    /// main app side returns "service not found" because launchd never
    /// registered the name; both the auto-connector and the resetPairings
    /// flow's β-probe depend on this entry to ever reach the agent.
    static let defaultRemoteAgent = LaunchAgentInstaller.PlistConfig(
        label: "com.termura.remote-agent",
        executablePath: "/Applications/Termura.app/Contents/Helpers/termura-remote-agent",
        runAtLoad: true,
        machServices: ["com.termura.remote-agent"]
    )
}
