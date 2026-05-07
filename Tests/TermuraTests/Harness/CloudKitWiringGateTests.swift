// Pins the CloudKit-gate semantics so a future env-var rename or
// inversion can't silently re-introduce the cross-network pairing
// regression that motivated flipping the gate to opt-out: previously
// Mac required `TERMURA_REMOTE_ENABLE_CLOUDKIT=1`, no scheme set it,
// and iOS pair-init records sat unread in the inbox forever.
//
// The decision is exercised through the pure
// `cloudKitEnabledForEnvironment` helper instead of the full
// `makeCloudKitWiring` so the test never instantiates `CKContainer`
// (which would trap on un-provisioned iCloud containers).

import Foundation
@testable import Termura
import Testing

@Suite("RemoteServerHarness.cloudKitEnabledForEnvironment")
struct CloudKitWiringGateTests {
    @Test("default empty environment enables CloudKit")
    func defaultEnvEnablesCloudKit() {
        #expect(RemoteServerHarness.cloudKitEnabledForEnvironment([:]) == true)
    }

    @Test("explicit DISABLE=1 turns CloudKit off")
    func disableSwitchTurnsCloudKitOff() {
        let env = ["TERMURA_REMOTE_DISABLE_CLOUDKIT": "1"]
        #expect(RemoteServerHarness.cloudKitEnabledForEnvironment(env) == false)
    }

    @Test("non-\"1\" values do not disable CloudKit (strict kill-switch)")
    func nonOneValuesKeepCloudKitEnabled() {
        for value in ["0", "true", "yes", "TRUE", " 1", "1 ", ""] {
            let env = ["TERMURA_REMOTE_DISABLE_CLOUDKIT": value]
            #expect(
                RemoteServerHarness.cloudKitEnabledForEnvironment(env) == true,
                "value=\(value) should not disable CloudKit"
            )
        }
    }

    @Test("legacy ENABLE env var has no effect after the gate flip")
    func legacyEnableEnvIgnored() {
        // Pre-flip Mac required this. Test pins that it's now a no-op
        // so a stale dev environment carrying the old var doesn't
        // mask a regression.
        let env = ["TERMURA_REMOTE_ENABLE_CLOUDKIT": "0"]
        #expect(RemoteServerHarness.cloudKitEnabledForEnvironment(env) == true)
    }

    /// Wave 6 regression. Mac direct-distribution archives can't rely
    /// on `aps-environment` always delivering silent push (cold-start
    /// APNs registration races, iCloud account refreshes, push
    /// subscription server-side fires that never reach the client).
    /// Poll cadence is the only delivery floor in those windows. The
    /// package-level CloudKitTransport default is 60s, calibrated for
    /// iOS where push is the primary path; Mac has been observed in
    /// the field taking 60-120s for cross-network pair handshake when
    /// push didn't fire. The harness now overrides to 5s on Mac. This
    /// test pins the constant so a regression to the public default
    /// surfaces at compile/test time, not in the field.
    @Test("Mac CloudKitTransport poll cadence is 5s, not the package default 60s")
    func macPollIntervalIsFiveSeconds() {
        let cadence = RemoteServerHarness.macPollInterval
        #expect(cadence == .seconds(5),
                "Mac harness must override CloudKitTransport pollInterval — fix slow pair handshake regression")
        let configuration = RemoteServerHarness.macCloudKitTransportConfiguration()
        #expect(configuration.pollInterval == .seconds(5),
                "Configuration helper must propagate the constant verbatim")
    }
}
