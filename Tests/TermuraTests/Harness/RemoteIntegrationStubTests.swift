import Foundation
@testable import Termura
import TermuraRemoteProtocol
import XCTest

/// PR9 Step 2 — pins the Free-build behaviour of the public stubs so a
/// future protocol extension can't silently swap the contract that the
/// `RemoteControlController` happy path relies on. These tests stay
/// dependency-free; they do not construct the controller.
final class RemoteIntegrationStubTests: XCTestCase {
    // MARK: - NullRemoteIntegration

    func test_NullRemoteIntegration_revokeAllPairedDevices_returnsEmpty() async throws {
        let null = NullRemoteIntegration()
        let revoked = try await null.revokeAllPairedDevices()
        XCTAssertTrue(revoked.isEmpty,
                      "Free build has no pairings; revokeAll must return [] not throw")
    }

    func test_NullRemoteIntegration_resetPairingState_throwsIntegrationDisabled() async {
        let null = NullRemoteIntegration()
        do {
            try await null.resetPairingState()
            XCTFail("expected resetPairingState to throw integrationDisabled on the Free build")
        } catch RemoteAdapterError.integrationDisabled {
            // ok
        } catch {
            XCTFail("expected integrationDisabled, got \(error)")
        }
    }

    // MARK: - NullRemoteAgentBridgeLifecycle

    func test_NullRemoteAgentBridgeLifecycle_resetAgentState_isNoop() async throws {
        let bridge = NullRemoteAgentBridgeLifecycle()
        // No-op contract: must complete without throwing so a Free-build
        // resetPairings happy path doesn't surface a phantom error when
        // the harness isn't wired in.
        try await bridge.resetAgentState()
    }
}
