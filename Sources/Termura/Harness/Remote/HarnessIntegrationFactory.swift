// Wave 1 — `install()` registers the harness's real factory closures
// into `HarnessBootstrap` (defined in the public stub) so the public
// `RemoteIntegrationLauncher` dispatches to them at runtime instead
// of routing through `#if HARNESS_ENABLED` in the public stub.
//
// `install()` is idempotent and called from
// `HarnessBootstrap.runIfNeeded()`, which itself runs at the very first
// line of `AppDelegate.init`. In the Free build this whole file is
// absent (it lives only in the private repo) and the `#if HARNESS_ENABLED`
// branch in `HarnessBootstrap.runOneTimeInstallIfPossible()` stays out
// of the binary — the closures remain `nil`, the launcher falls back
// to `NullRemoteIntegration`/`NullRemoteAgentBridgeLifecycle`.

import Foundation

@MainActor
enum HarnessIntegrationFactory {
    /// Wires the harness's real factory implementations into the public
    /// launcher. Idempotent — repeat calls overwrite the same closures
    /// with structurally identical ones, preserving the
    /// single-write-at-startup invariant documented on
    /// `HarnessBootstrap.integrationFactory`.
    static func install() {
        HarnessBootstrap.setIntegrationFactory { adapter in
            RemoteServerHarness(adapter: adapter)
        }
        HarnessBootstrap.setAgentBridgeFactory { integration in
            guard let harness = integration as? RemoteServerHarness else {
                return NullRemoteAgentBridgeLifecycle()
            }
            return RemoteAgentBridgeAssembly(harness: harness)
        }
        // Wave 8 — agent event source factory. The cwd resolver is
        // injected later by `AppDelegate.makeRemoteAdapter` (it
        // captures the active `ProjectCoordinator`) via
        // `HarnessBootstrap.installAgentEventSource(cwdResolver:)`,
        // which then runs this factory to produce the singleton.
        HarnessBootstrap.setAgentEventSourceFactory { cwdResolver in
            LiveAgentEventSource(cwdResolver: cwdResolver)
        }
    }
}
