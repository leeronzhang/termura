import Foundation
@testable import Termura
import TermuraRemoteProtocol
import Testing

// D-1 — pins the drain wiring on `RemoteControlController`:
// pre-fix the kit-internal `CloudKitReplyChannel.send` failure was
// caught + logged at the router and the user saw a frozen iPhone
// with no actionable hint. The new contract is:
//   1. happy path  — emitted failure surfaces in `lastError` tagged
//                    `.transport`
//   2. error path  — drain Task does not crash on a stream that
//                    finishes immediately (Free-build / Null-integration
//                    default).
//   3. lifecycle   — `stopTransportFailureDrain()` cancels the drain
//                    Task so a subsequent `start` does not leave two
//                    drains running against the same stream.
@Suite("RemoteControlController transport-failure drain (D-1)")
@MainActor
struct RemoteControlTransportFailureTests {
    @Test("emitted failure surfaces in lastError tagged .transport")
    func emittedFailureSurfacesAsTransportError() async throws {
        let integration = EmittingTransportFailureIntegration()
        let controller = makeController(integration: integration)
        controller.startTransportFailureDrain()
        let peer = UUID()
        await integration.emit(RemoteTransportFailure(
            peerDeviceId: peer,
            reason: "simulated CK quota",
            occurredAt: Date(timeIntervalSince1970: 1000)
        ))
        await waitUntil { controller.lastError != nil }
        #expect(controller.lastErrorOrigin == .transport,
                "drain must tag transport failures distinctly so helper-health auto-clear cannot wipe them")
        let message = try #require(controller.lastError)
        #expect(message.contains("simulated CK quota"),
                "drain message must surface the gateway error reason")
        #expect(message.contains(String(peer.uuidString.prefix(8))),
                "drain message must include peer prefix so user can correlate to a specific device")
        controller.stopTransportFailureDrain()
    }

    @Test("default empty stream completes without setting lastError")
    func emptyStreamCompletesWithoutSettingError() async {
        // NullRemoteIntegration inherits the default empty stream;
        // the drain Task should fall through cleanly and never touch
        // lastError.
        let controller = makeController(integration: NullRemoteIntegration())
        controller.startTransportFailureDrain()
        for _ in 0 ..< 8 {
            await Task.yield()
        }
        #expect(controller.lastError == nil,
                "default-empty stream must not synthesise a phantom error")
        #expect(controller.lastErrorOrigin == nil)
        controller.stopTransportFailureDrain()
    }

    @Test("stop cancels drain task so post-stop emissions do not surface")
    func stopDrainCancelsTask() async {
        let integration = EmittingTransportFailureIntegration()
        let controller = makeController(integration: integration)
        controller.startTransportFailureDrain()
        #expect(controller.transportFailureDrainTask != nil,
                "start must spawn the drain task")
        controller.stopTransportFailureDrain()
        #expect(controller.transportFailureDrainTask == nil,
                "stop must release the drain handle so disable/enable cannot leak tasks")
        await integration.emit(RemoteTransportFailure(
            peerDeviceId: UUID(),
            reason: "after-stop",
            occurredAt: Date(timeIntervalSince1970: 2000)
        ))
        for _ in 0 ..< 8 {
            await Task.yield()
        }
        #expect(controller.lastError == nil,
                "post-stop emissions must not surface — drain must really cancel, not just detach")
    }

    private func makeController(integration: any RemoteIntegration) -> RemoteControlController {
        RemoteControlController(
            integration: integration,
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: UserDefaults(suiteName: "termura-d1-drain-tests-\(UUID().uuidString)") ?? .standard
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 100 {
            if condition() { return }
            await Task.yield()
        }
    }
}

/// Test integration that emits `RemoteTransportFailure` on demand
/// via its own AsyncStream. Mirrors what the harness does in
/// production but without dragging the kit-internal CloudKit
/// transport into the controller-side test.
private actor EmittingTransportFailureIntegration: RemoteIntegration {
    private let stream: AsyncStream<RemoteTransportFailure>
    private let continuation: AsyncStream<RemoteTransportFailure>.Continuation
    private(set) var isRunning = false

    init() {
        let made = AsyncStream.makeStream(of: RemoteTransportFailure.self)
        stream = made.stream
        continuation = made.continuation
    }

    deinit {
        continuation.finish()
    }

    nonisolated func transportFailures() -> AsyncStream<RemoteTransportFailure> {
        stream
    }

    func emit(_ failure: RemoteTransportFailure) {
        continuation.yield(failure)
    }

    func start() async throws { isRunning = true }
    func stop() async { isRunning = false }

    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(
            token: "stub-token",
            macPublicKey: Data([0x01]),
            serviceName: "stub-mac",
            expiresAt: Date(timeIntervalSince1970: 9_999_999)
        )
    }

    func notifyPushReceived() async {}
    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }
    func revokePairedDevice(id _: UUID) async throws {}
    func revokeAllPairedDevices() async throws -> [UUID] { [] }
    func resetPairingState() async throws {}
    func auditLog() async throws -> [RemoteAuditEntry] { [] }
}
