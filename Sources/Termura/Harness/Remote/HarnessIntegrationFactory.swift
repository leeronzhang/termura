import Foundation

/// Direct factories for the harness's runtime types. Pre-PR3 this enum
/// registered closure factories into `HarnessBootstrap`'s slot table so
/// the public stub could route across an `#if HARNESS_ENABLED` boundary;
/// PR3 inlined the harness implementation into the public repo, so the
/// indirection is gone and the launcher calls these functions directly.
@MainActor
enum HarnessIntegrationFactory {
    static func make(adapter: any RemoteSessionsAdapter) -> any RemoteIntegration {
        RemoteServerHarness(adapter: adapter)
    }

    static func makeAgentBridge(integration: any RemoteIntegration) -> any RemoteAgentBridgeLifecycle {
        guard let harness = integration as? RemoteServerHarness else {
            // Non-harness integrations (e.g. test injectables) supply their
            // own bridge or skip the bridge entirely; return a no-op so
            // `start/stop/resetAgentState` calls remain safe.
            return NullRemoteAgentBridgeLifecycle()
        }
        return RemoteAgentBridgeAssembly(harness: harness)
    }
}
