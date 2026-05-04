import Foundation
@testable import TermuraRemoteClient
import TermuraRemoteProtocol
import Testing

// D-3 — pins the hard-circuit-breaker contract on
// `CloudKitClientTransport`: pre-fix sustained gateway failures
// plateaued at `backoffCap` (600 s) forever, so a stuck CloudKit
// outage drained battery + cellular data on the iOS side without
// any way to halt. The breaker now flips after
// `circuitBreakerThreshold` consecutive failures and stops the
// poll loop entirely; recovery is via `disconnect()` + the next
// reconnect cycle (the iOS reconnect controller's natural path
// when the user pulls down to refresh or re-enters foreground).

@Suite("CloudKitClientTransport circuit breaker (D-3)")
struct CloudKitClientCircuitBreakerTests {
    @Test("pollHealth.isCircuitOpen flips after threshold consecutive failures")
    func breakerFlipsAtThreshold() async throws {
        let phoneId = UUID()
        let macId = UUID()
        let gateway = SwitchableFetchClientGateway(
            error: CloudKitGatewayError.backingFailure(reason: "simulated outage")
        )
        let transport = CloudKitClientTransport(
            localDeviceId: phoneId,
            peerDeviceId: macId,
            gateway: gateway,
            configuration: .init(
                pollInterval: .seconds(3600),
                circuitBreakerThreshold: 3
            ),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        try await transport.connect()
        await gateway.beginFailing()
        for _ in 0 ..< 3 {
            await transport.ingestPushNotification()
        }
        let health = await transport.pollHealth()
        #expect(health.isCircuitOpen,
                "breaker must open at circuitBreakerThreshold (3) consecutive failures")
        // `>= 3` not `== 3` because the background poll loop spawned
        // by connect() races against the explicit pushes — its first
        // iteration may fire after `beginFailing()` lands and add an
        // extra failure to the counter.
        #expect(health.consecutiveFailures >= 3)
        #expect(health.lastFailureReason?.contains("simulated outage") == true)
        await transport.disconnect()
    }

    @Test("disconnect() resets breaker so the next connect() re-arms cleanly")
    func disconnectResetsBreaker() async throws {
        let phoneId = UUID()
        let macId = UUID()
        let gateway = SwitchableFetchClientGateway(
            error: CloudKitGatewayError.backingFailure(reason: "outage")
        )
        let transport = CloudKitClientTransport(
            localDeviceId: phoneId,
            peerDeviceId: macId,
            gateway: gateway,
            configuration: .init(pollInterval: .seconds(3600), circuitBreakerThreshold: 2),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        try await transport.connect()
        await gateway.beginFailing()
        for _ in 0 ..< 2 {
            await transport.ingestPushNotification()
        }
        var health = await transport.pollHealth()
        #expect(health.isCircuitOpen, "preconditions: breaker must be open before disconnect()")
        await transport.disconnect()
        health = await transport.pollHealth()
        #expect(!health.isCircuitOpen,
                "disconnect() must reset breaker so the next reconnect cycle is the natural recovery path")
        #expect(health.consecutiveFailures == 0)
    }

    @Test("default threshold is 16 — matches server side")
    func defaultThresholdSymmetric() {
        let config = CloudKitClientTransport.Configuration()
        #expect(config.circuitBreakerThreshold == 16,
                "client default must match server so both sides degrade identically")
    }
}

/// Test gateway whose fetch can be toggled between "succeed empty"
/// and "throw simulated outage" so a test can let `connect()` succeed
/// (initial backlog fetch returns empty page) and then drive failures
/// through the poll loop.
actor SwitchableFetchClientGateway: CloudKitDatabaseGateway {
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
