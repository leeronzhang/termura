import Foundation
import Testing

/// PR8 Phase 2 §11.2 — open-core boundary check. The public-repo
/// `AppDelegate+RemoteBridge.swift` and `RemoteIntegration+Stub.swift`
/// must never reference any harness-private concrete type or import
/// the harness Clang module. Any leak would re-couple the open-core
/// repo to the private one and re-introduce the PR3 problem.
@Suite("Open-core boundary — agent bridge surface")
struct AgentBoundaryTests {
    private static let bannedTokens: [String] = [
        "RemoteAgentBridgeAssembly",
        "RemoteAgentXPCClient",
        "AppMailboxXPCBridge",
        "AgentInjectedCloudKitIngress",
        "TrustedSourceGate",
        "AgentVirtualReplyChannel",
        "RemoteAgentAutoConnector",
        "TermuraAgentXPCInterfaces",
        "AgentBridgeProtocol",
        "AppMailboxProtocol",
        "XPCMailboxItem",
        "../termura-harness"
    ]

    private static func publicFile(named relative: String) -> URL? {
        // Tests run with $CWD inside the build sandbox; #file is the
        // most reliable anchor.
        let testFile = URL(fileURLWithPath: #filePath)
        var dir = testFile.deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    @Test("AppDelegate+RemoteBridge.swift contains no harness concrete tokens")
    func bridgeFileHasNoLeakage() throws {
        guard let url = Self.publicFile(named: "Sources/Termura/App/AppDelegate+RemoteBridge.swift") else {
            Issue.record("could not locate AppDelegate+RemoteBridge.swift")
            return
        }
        let body = try String(contentsOf: url, encoding: .utf8)
        for token in Self.bannedTokens {
            #expect(!body.contains(token), "AppDelegate+RemoteBridge.swift leaked \(token)")
        }
    }

    @Test("RemoteIntegration+Stub.swift contains no harness concrete tokens")
    func stubFileHasNoLeakage() throws {
        guard let url = Self.publicFile(named: "Sources/Termura/Harness/RemoteIntegration+Stub.swift") else {
            Issue.record("could not locate RemoteIntegration+Stub.swift")
            return
        }
        let body = try String(contentsOf: url, encoding: .utf8)
        for token in Self.bannedTokens {
            #expect(!body.contains(token), "RemoteIntegration+Stub.swift leaked \(token)")
        }
    }

    @Test("AppDelegate.swift only references RemoteAgentBridgeLifecycle through factory")
    func appDelegateOnlyTouchesProtocol() throws {
        guard let url = Self.publicFile(named: "Sources/Termura/App/AppDelegate.swift") else {
            Issue.record("could not locate AppDelegate.swift")
            return
        }
        let body = try String(contentsOf: url, encoding: .utf8)
        for token in Self.bannedTokens {
            #expect(!body.contains(token), "AppDelegate.swift leaked \(token)")
        }
    }

    /// PR9 — extend boundary coverage to every public-repo file added
    /// or substantially modified by the disable / revokeAll /
    /// resetPairings work. Any future edit that imports a private
    /// clang module or pastes a private impl type name will trip
    /// this scan.
    @Test(
        "PR9 controller / probe / fallback / settings files contain no harness concrete tokens",
        arguments: [
            "Sources/Termura/Services/RemoteControlController.swift",
            "Sources/Termura/Services/RemoteControlController+Actions.swift",
            "Sources/Termura/Services/AgentDeathProbe.swift",
            "Sources/Termura/Services/AgentKeychainFallbackCleaner.swift",
            "Sources/Termura/Views/RemoteControlSettingsView.swift",
            "Sources/Termura/Views/RemoteControlSettingsView+DangerZone.swift"
        ]
    )
    func pr9PublicFilesHaveNoLeakage(relativePath: String) throws {
        guard let url = Self.publicFile(named: relativePath) else {
            Issue.record("could not locate \(relativePath)")
            return
        }
        let body = try String(contentsOf: url, encoding: .utf8)
        for token in Self.bannedTokens {
            #expect(!body.contains(token), "\(relativePath) leaked \(token)")
        }
    }
}
