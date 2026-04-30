// Static identity of the remote-agent LaunchAgent — the parts of its
// plist that don't depend on where Termura.app currently lives. The
// executable path is intentionally NOT part of this struct: PR10 routes
// the executable path through `RemoteHelperPathResolving` so each
// install reflects the running .app's actual on-disk location.
//
// `RemoteControlController` owns one of these and combines it with a
// resolver-derived path at runtime to produce a `PlistConfig` ready
// for `LaunchAgentInstaller.install(...)`.

import Foundation

struct RemoteAgentMetadata: Sendable, Equatable {
    let label: String
    let runAtLoad: Bool
    let machServices: [String]

    static let `default` = RemoteAgentMetadata(
        label: "com.termura.remote-agent",
        runAtLoad: true,
        // Without this entry launchd never registers the bootstrap mach
        // service, so `NSXPCConnection(machServiceName:)` from the main
        // app side would always invalidate. Both the auto-connector and
        // the resetPairings β-probe depend on the entry to ever reach
        // the agent.
        machServices: ["com.termura.remote-agent"]
    )
}
