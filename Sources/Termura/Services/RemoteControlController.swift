// Bridges the actor-isolated `RemoteIntegration` to the SwiftUI
// settings layer. Exposes synchronous-readable observable state
// (`isEnabled`, `latestInvitationJSON`, `lastError`) so the toggle
// and invitation pasteboard never leak actor hops into the view.
//
// `enable()` also installs the per-user LaunchAgent plist (validated
// via `RemoteHelperPathResolving` — file exists + executable) so
// `~/Library/LaunchAgents/com.termura.remote-agent.plist` matches
// the in-app state on every transition; `disable()` removes it. The
// `resetPairings` install step skips the validation gate to preserve
// best-effort teardown semantics.

import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteControlController")

/// Why an entry was written to `lastError`. PR10 Step 3 fix —
/// `reinstallIfNeeded` only auto-clears messages tagged
/// `.helperHealth`; everything else is owned by other controller
/// surfaces (integration / pairing / revoke / reset /
/// generateInvitation) and must not be silently mutated by the
/// re-alignment pass. `.transport` (D-1) covers out-of-band
/// failures observed by the drain Task on
/// `integration.transportFailures()`; see
/// `RemoteControlController+TransportFailures.swift`.
enum RemoteControlErrorOrigin: Sendable, Equatable {
    case helperHealth
    case other
    case transport
}

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
    /// PR10 Step 3 fix — companion to `lastError`. `helperHealth` means
    /// "this message came from a helper-bundling / install / reinstall
    /// path"; `reinstallIfNeeded` clears stale messages tagged this way
    /// when it observes the helper recovered. `other` means "anything
    /// else" (integration / pairing / revoke / reset / generateInvitation)
    /// and is never auto-cleared by reinstallIfNeeded. Always paired
    /// with `lastError` via `setHelperError` / `setOtherError` /
    /// `clearLastError` so the two fields cannot drift.
    private(set) var lastErrorOrigin: RemoteControlErrorOrigin?
    var pairedDevices: [PairedDeviceSummary] = []
    var auditEntries: [RemoteAuditEntry] = []

    /// D-1 — owned by `+TransportFailures.swift`; see that file for
    /// lifecycle. Non-nil only while the controller is enabled.
    var transportFailureDrainTask: Task<Void, Never>?

    let integration: any RemoteIntegration
    let agentBridge: any RemoteAgentBridgeLifecycle
    let userDefaults: any UserDefaultsStoring
    let codec: any RemoteCodec
    let installer: LaunchAgentInstaller
    let agentMetadata: RemoteAgentMetadata
    let helperResolver: any RemoteHelperPathResolving
    let clock: any AppClock
    let agentDeathProbe: any AgentDeathProbing
    let fallbackCleaner: any AgentKeychainFallbackCleaning

    init(
        integration: any RemoteIntegration,
        agentBridge: any RemoteAgentBridgeLifecycle,
        userDefaults: any UserDefaultsStoring,
        installer: LaunchAgentInstaller = LaunchAgentInstaller(),
        agentMetadata: RemoteAgentMetadata = .default,
        helperResolver: any RemoteHelperPathResolving = LiveRemoteHelperPathResolver(),
        codec: any RemoteCodec = JSONRemoteCodec(),
        clock: any AppClock = LiveClock(),
        agentDeathProbe: any AgentDeathProbing = AgentDeathProbe(),
        fallbackCleaner: any AgentKeychainFallbackCleaning = AgentKeychainFallbackCleaner()
    ) {
        self.integration = integration
        self.agentBridge = agentBridge
        self.userDefaults = userDefaults
        self.installer = installer
        self.agentMetadata = agentMetadata
        self.helperResolver = helperResolver
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
            setOtherError(error.localizedDescription)
            logger.error("Failed to start remote integration: \(error.localizedDescription)")
            return
        }
        do {
            try validateHelperBundled()
        } catch {
            let message = describe(helperError: error)
            setHelperError(message)
            logger.error("Helper validation failed; rolling back integration: \(message)")
            await integration.stop()
            return
        }
        do {
            try await installer.install(runtimePlistConfig())
            recordFingerprintAfterInstall()
            setEnabledFlag(true)
            clearLastError()
            startTransportFailureDrain()
            logger.info("Remote control enabled and LaunchAgent installed")
        } catch {
            setHelperError("Server started but plist install failed: \(error.localizedDescription)")
            logger.error("Plist install failed; rolling back: \(error.localizedDescription)")
            await integration.stop()
        }
    }

    /// Builds a `PlistConfig` from the static `RemoteAgentMetadata` and
    /// the resolver's current helper path. Both `enable()` and the
    /// `resetPairings` install step (PR9) consume this; `enable()` gates
    /// it behind `validateHelperBundled()`, while `resetPairings` does
    /// not so the best-effort teardown remains unchanged.
    func runtimePlistConfig() -> LaunchAgentInstaller.PlistConfig {
        LaunchAgentInstaller.PlistConfig(
            label: agentMetadata.label,
            executablePath: helperResolver.helperExecutableURL().path,
            runAtLoad: agentMetadata.runAtLoad,
            machServices: agentMetadata.machServices
        )
    }

    /// Fails closed when the resolver-derived helper binary is missing
    /// or non-executable. Called by `enable()` only — `resetPairings`
    /// must keep working in degraded states (PR9 §12.6.1 invariant).
    private func validateHelperBundled() throws(RemoteHelperError) {
        let path = helperResolver.helperExecutableURL().path
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            throw .helperNotBundled(path: path)
        }
        guard fileManager.isExecutableFile(atPath: path) else {
            throw .helperNotExecutable(path: path)
        }
    }

    private func describe(helperError: RemoteHelperError) -> String {
        switch helperError {
        case let .helperNotBundled(path):
            "Remote helper not bundled at \(path)."
        case let .helperNotExecutable(path):
            "Remote helper at \(path) is not executable."
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

    /// Records a helper-bundling / install / reinstall failure.
    /// `reinstallIfNeeded` is allowed to silently clear messages
    /// tagged this way once the helper recovers.
    func setHelperError(_ message: String) {
        lastError = message
        lastErrorOrigin = .helperHealth
    }

    /// Records any error that is NOT a helper-bundling concern
    /// (integration / pairing / revoke / reset / invitation).
    /// `reinstallIfNeeded` will not auto-clear these.
    func setOtherError(_ message: String) {
        lastError = message
        lastErrorOrigin = .other
    }

    /// D-1 — records an out-of-band transport failure observed by the
    /// drain Task on `integration.transportFailures()`. Must live here
    /// (not in `+TransportFailures.swift`) because `lastErrorOrigin`
    /// is `private(set)` and Swift's file-private setter access blocks
    /// cross-file extensions from writing it.
    func setTransportError(_ message: String) {
        lastError = message
        lastErrorOrigin = .transport
    }

    /// Clears both the message and the origin tag together so the two
    /// observable fields can never drift apart.
    func clearLastError() {
        lastError = nil
        lastErrorOrigin = nil
    }

    func generateInvitation() async {
        guard isEnabled, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let invitation = try await integration.issueInvitation()
            let data = try codec.encode(invitation)
            guard let json = String(data: data, encoding: .utf8) else {
                setOtherError("Failed to render invitation")
                return
            }
            latestInvitationJSON = json
            clearLastError()
        } catch {
            setOtherError(error.localizedDescription)
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
