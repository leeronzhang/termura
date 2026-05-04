import Foundation
import TermuraRemoteProtocol
@testable import TermuraRemoteServer
import Testing

// D-3 — pins the hard-circuit-breaker contract on
// `CloudKitTransport`: pre-fix sustained gateway failures
// plateaued at `backoffCap` (600 s) forever, so a stuck CloudKit
// outage drained battery + cellular data on the Mac side without
// any way to halt. The breaker now flips after
// `circuitBreakerThreshold` consecutive failures and stops the
// poll loop entirely; recovery is via `stop()` + `start()` (the
// Settings-toggle off/on path) which resets the breaker.

@Suite("CloudKitTransport circuit breaker (D-3)")
struct CloudKitTransportCircuitBreakerTests {
    @Test("pollHealth.isCircuitOpen flips after threshold consecutive failures")
    func breakerFlipsAtThreshold() async throws {
        let macId = UUID()
        // Initial backlog fetch (in start()) must succeed so the
        // transport reaches runnable state; subsequent fetches fail
        // so we can drive the breaker via ingestPushNotification.
        let gateway = SwitchableFetchGateway(
            error: CloudKitGatewayError.backingFailure(reason: "simulated outage")
        )
        let transport = CloudKitTransport(
            name: "mac",
            deviceId: macId,
            gateway: gateway,
            configuration: .init(
                pollInterval: .seconds(3600),
                circuitBreakerThreshold: 3
            ),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        try await transport.start(handler: NoopHandler())
        await gateway.beginFailing()
        for _ in 0 ..< 3 {
            await transport.ingestPushNotification()
        }
        let health = await transport.pollHealth()
        #expect(health.isCircuitOpen,
                "breaker must open at circuitBreakerThreshold (3) consecutive failures")
        // `>= 3` not `== 3` because the background poll loop spawned
        // by start() races against the explicit pushes — its first
        // iteration may fire after `beginFailing()` lands and add an
        // extra failure to the counter. The breaker contract is
        // "open at threshold or beyond", not "exactly at threshold".
        #expect(health.consecutiveFailures >= 3)
        #expect(health.lastFailureReason?.contains("simulated outage") == true)
        await transport.stop()
    }

    @Test("stop() resets breaker so next start() polls cleanly")
    func stopResetsBreaker() async throws {
        let macId = UUID()
        let gateway = SwitchableFetchGateway(
            error: CloudKitGatewayError.backingFailure(reason: "outage")
        )
        let transport = CloudKitTransport(
            name: "mac",
            deviceId: macId,
            gateway: gateway,
            configuration: .init(pollInterval: .seconds(3600), circuitBreakerThreshold: 2),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        try await transport.start(handler: NoopHandler())
        await gateway.beginFailing()
        for _ in 0 ..< 2 {
            await transport.ingestPushNotification()
        }
        var health = await transport.pollHealth()
        #expect(health.isCircuitOpen, "preconditions: breaker must be open before stop()")
        await transport.stop()
        await gateway.stopFailing()
        try await transport.start(handler: NoopHandler())
        health = await transport.pollHealth()
        #expect(!health.isCircuitOpen,
                "stop() must reset breaker so toggle-off-on recovery is the natural path")
        #expect(health.consecutiveFailures == 0,
                "stop() must reset the failure counter alongside the breaker")
        await transport.stop()
    }

    @Test("breaker tolerance default is 16 — higher than agent autoConnector")
    func defaultThresholdIsConservative() {
        // CloudKit failures are usually transient network issues, not
        // configuration mistakes (which is what the agent autoConnector's
        // 8-failure threshold targets). Pin the default so a future
        // tuning change is reviewer-visible.
        let config = CloudKitTransport.Configuration()
        #expect(config.circuitBreakerThreshold == 16,
                "default must be 16 so transient Wi-Fi drops do not aggressively halt polling")
    }
}

/// Test gateway whose fetch can be toggled between "succeed empty"
/// and "throw simulated outage" so a test can let `start()` succeed
/// (initial backlog fetch returns empty page) and then drive failures
/// through the poll loop. Save / delete are no-op success so the
/// breaker test exercises only the poll-failure path.
actor SwitchableFetchGateway: CloudKitDatabaseGateway {
    private let error: any Error
    private var failing = false

    init(error: any Error) {
        self.error = error
    }

    func beginFailing() {
        failing = true
    }

    func stopFailing() {
        failing = false
    }

    func save(_: CloudKitEnvelopeRecord) async throws {}

    func fetch(targetDeviceId _: UUID, since _: Date) async throws -> CloudKitFetchPage {
        if failing { throw error }
        return CloudKitFetchPage(records: [])
    }

    func delete(id _: String) async throws {}
}

actor NoopHandler: EnvelopeHandler {
    func handle(envelope _: Envelope, replyChannel _: any ReplyChannel) async {}
    func connectionClosed(channelId _: UUID) async {}
}
