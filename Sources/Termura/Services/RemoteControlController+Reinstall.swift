// PR10 Step 3 — `reinstallIfNeeded()` and the fingerprint persistence
// helpers it depends on. Lives in its own extension so the controller
// surface stays under the 250-line soft cap; functionally part of the
// same observable type as `RemoteControlController`.

import Foundation
import OSLog

private let logger = Logger(
    subsystem: "com.termura.app",
    category: "RemoteControlController+Reinstall"
)

extension RemoteControlController {
    /// Silent re-alignment of the on-disk plist with the currently
    /// running `Termura.app`. Invoked at app launch (and available
    /// for callers that detect an upgrade). Contract:
    ///
    /// - `isEnabled == false`: no-op. The user has not asked for
    ///   remote-control to be running; leaving stale plist alone is
    ///   correct.
    /// - helper missing at the resolved path: record `lastError` but
    ///   do NOT auto-disable. `isEnabled` reflects user intent, not
    ///   helper health (PR10 invariant).
    /// - plist points at a different path OR the helper binary's
    ///   fingerprint differs from the last successful install: re-run
    ///   `installer.install(...)`. The installer's existing
    ///   bootout-then-bootstrap is idempotent and covers both relocate
    ///   (path drift) and upgrade (binary changed).
    /// - everything aligned: no-op.
    func reinstallIfNeeded() async {
        guard isEnabled else { return }
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let lastFingerprint = readLastInstalledFingerprint()
        let health = RemoteHelperHealth.inspect(
            resolver: helperResolver,
            installer: installer,
            label: agentMetadata.label,
            lastInstalledFingerprint: lastFingerprint
        )
        guard health.resolvedExists else {
            let path = health.resolvedExecutablePath
            setHelperError("Remote helper missing at \(path); LaunchAgent not re-aligned.")
            logger.error("reinstallIfNeeded: helper missing at \(path); leaving isEnabled untouched")
            return
        }
        let needsReinstall = !health.matchesInstalled || !health.fingerprintMatchesLastInstall
        guard needsReinstall else {
            // Healthy and aligned. Drop any stale helper-class error
            // (e.g. a previous "Remote helper missing at ..." that
            // was true at the time but the helper has since recovered).
            // We only clear when the message is helper-owned so we
            // don't accidentally erase a pending revoke/reset/integration
            // error written by another controller surface.
            if lastErrorOrigin == .helperHealth {
                clearLastError()
                logger.info("reinstallIfNeeded: helper recovered; cleared stale helperHealth error")
            }
            return
        }
        do {
            try await installer.install(runtimePlistConfig())
            recordFingerprintAfterInstall()
            clearLastError()
            logger.info(
                "reinstallIfNeeded: re-aligned plist to \(health.resolvedExecutablePath, privacy: .public)"
            )
        } catch {
            setHelperError("reinstallIfNeeded plist install failed: \(error.localizedDescription)")
            logger.error("reinstallIfNeeded install failed: \(error.localizedDescription)")
        }
    }

    /// Synchronous read-only diagnostic snapshot. Composes resolver +
    /// installer + persisted fingerprint into a `RemoteHelperHealth`.
    /// Safe to call from SwiftUI (the controller is `@MainActor`); no
    /// network or actor hops, only file-system stat + UserDefaults read.
    /// Callers that just want a single freshness check (Settings view,
    /// danger-zone diagnostics, future health-readout UIs) should
    /// prefer this over re-implementing the inspector composition.
    func helperHealth() -> RemoteHelperHealth {
        RemoteHelperHealth.inspect(
            resolver: helperResolver,
            installer: installer,
            label: agentMetadata.label,
            lastInstalledFingerprint: readLastInstalledFingerprint()
        )
    }

    /// Captures the helper binary's fingerprint right after a successful
    /// `installer.install(...)`. Used by `reinstallIfNeeded` to detect
    /// helper-binary upgrades that don't change the install path.
    /// Failure is swallowed: the helper file vanishing between install
    /// and stat would only mean we don't have a recorded fingerprint —
    /// next launch's `reinstallIfNeeded` treats "no record" as "no
    /// mismatch" and is harmless.
    func recordFingerprintAfterInstall() {
        let path = helperResolver.helperExecutableURL().path
        guard let fingerprint = RemoteHelperFingerprint.read(at: path) else {
            logger.debug("recordFingerprintAfterInstall: could not stat \(path, privacy: .public)")
            return
        }
        do {
            let data = try JSONEncoder().encode(fingerprint)
            userDefaults.set(data, forKey: AppConfig.UserDefaultsKeys.remoteHelperLastInstalledFingerprint)
        } catch {
            // Non-critical: we lose one round of upgrade detection.
            logger.debug("recordFingerprintAfterInstall: encode failed: \(error.localizedDescription)")
        }
    }

    /// Reads the JSON-encoded fingerprint stored by
    /// `recordFingerprintAfterInstall`. Returns `nil` for "never
    /// installed" or "stored data corrupt"; both branches end up
    /// treated as "no recorded mismatch" upstream.
    func readLastInstalledFingerprint() -> RemoteHelperFingerprint? {
        guard let data = userDefaults.data(
            forKey: AppConfig.UserDefaultsKeys.remoteHelperLastInstalledFingerprint
        ) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(RemoteHelperFingerprint.self, from: data)
        } catch {
            logger.debug("readLastInstalledFingerprint: decode failed: \(error.localizedDescription)")
            return nil
        }
    }
}
