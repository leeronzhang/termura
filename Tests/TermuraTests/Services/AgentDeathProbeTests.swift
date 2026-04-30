import Foundation
@testable import Termura
import XCTest

/// PR9 Step 6 — `AgentDeathProbe` is the gate for fallback B in
/// `RemoteControlController.resetPairings`. These tests pin its
/// composition (grace period + injected probe-once → result):
///   * grace period actually fires before the probe attempt
///   * each `ProbeResult` from the probe-once closure passes through
///     the wrapper unchanged
/// The live `liveProbeOnce` NSXPC dance is deliberately not unit-
/// tested here — exercising it requires a real `NSXPCListener` on a
/// per-user mach name. The injected `probeOnce` lets controller-level
/// tests substitute a deterministic implementation.
final class AgentDeathProbeTests: XCTestCase {
    func test_confirmUnreachable_observesGracePeriodBeforeProbing() async {
        let clock = TestClock()
        let didProbe = LockedFlag()
        let probe = AgentDeathProbe(
            clock: clock,
            gracePeriod: .seconds(5),
            probeTimeout: .seconds(1),
            probeOnce: { _, _ in
                await didProbe.set(true)
                return .confirmedDead
            }
        )

        // Pre-condition: probe-once has not yet fired before the grace.
        let before = await didProbe.get()
        XCTAssertFalse(before)

        let result = await probe.confirmUnreachable(machServiceName: "test.mach")

        // The fake clock collapses sleep instantly; we just need to
        // verify the wrapper called sleep before invoking probe-once.
        XCTAssertEqual(clock.sleepCallCount, 1, "grace period must fire exactly once before probe")
        XCTAssertEqual(result, .confirmedDead)
        let after = await didProbe.get()
        XCTAssertTrue(after, "probe-once must run after grace, not be skipped")
    }

    func test_confirmUnreachable_passesThroughConfirmedDead() async {
        let probe = makeProbe(returning: .confirmedDead)
        let result = await probe.confirmUnreachable(machServiceName: "test.mach")
        XCTAssertEqual(result, .confirmedDead)
    }

    func test_confirmUnreachable_passesThroughPossiblyAlive() async {
        let probe = makeProbe(returning: .possiblyAlive)
        let result = await probe.confirmUnreachable(machServiceName: "test.mach")
        XCTAssertEqual(result, .possiblyAlive)
    }

    func test_confirmUnreachable_passesThroughIndeterminate() async {
        let probe = makeProbe(returning: .indeterminate)
        let result = await probe.confirmUnreachable(machServiceName: "test.mach")
        XCTAssertEqual(result, .indeterminate)
    }

    func test_confirmUnreachable_forwardsMachServiceNameToProbeOnce() async {
        let captured = Capturer()
        let probe = AgentDeathProbe(
            clock: TestClock(),
            gracePeriod: .seconds(5),
            probeTimeout: .seconds(1),
            probeOnce: { name, _ in
                await captured.set(name)
                return .indeterminate
            }
        )
        _ = await probe.confirmUnreachable(machServiceName: "com.termura.remote-agent")
        let value = await captured.value
        XCTAssertEqual(value, "com.termura.remote-agent")
    }

    private func makeProbe(returning result: ProbeResult) -> AgentDeathProbe {
        AgentDeathProbe(
            clock: TestClock(),
            gracePeriod: .seconds(5),
            probeTimeout: .seconds(1),
            probeOnce: { _, _ in result }
        )
    }
}

private actor LockedFlag {
    private(set) var value = false
    func get() -> Bool { value }
    func set(_ newValue: Bool) { value = newValue }
}

private actor Capturer {
    private(set) var value: String?
    func set(_ newValue: String) { value = newValue }
}
