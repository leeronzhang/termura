import Foundation
@testable import Termura
import Testing

/// PtyStreamCoalescer is a pure value type with deterministic flush
/// semantics — caller passes `now: Date` for every operation so tests
/// stay free of Clock or asynchronous-wait dependencies.
@Suite("PtyStreamCoalescer flush triggers")
struct PtyStreamCoalescerTests {
    private let zero = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Empty buffer never flushes regardless of elapsed time")
    func emptyBufferDoesNotFlush() {
        var coalescer = PtyStreamCoalescer()
        let chunks = coalescer.drainReadyChunks(at: zero.addingTimeInterval(10))
        #expect(chunks.isEmpty)
        #expect(!coalescer.hasPending)
    }

    @Test("Size threshold flushes when buffer reaches bytesThreshold")
    func flushesWhenSizeReached() {
        var coalescer = PtyStreamCoalescer(bytesThreshold: 8, timeThreshold: 1, idleCeiling: 10)
        coalescer.append(Data([1, 2, 3, 4]), at: zero)
        // Below threshold, time not elapsed → no flush.
        #expect(coalescer.drainReadyChunks(at: zero).isEmpty)
        coalescer.append(Data([5, 6, 7, 8]), at: zero)
        // Hits exactly bytesThreshold → flush at the same instant.
        let chunks = coalescer.drainReadyChunks(at: zero)
        #expect(chunks == [Data([1, 2, 3, 4, 5, 6, 7, 8])])
        #expect(!coalescer.hasPending)
    }

    @Test("One byte over the size threshold splits into two chunks")
    func boundaryOneByteOverEmitsTwoChunks() {
        var coalescer = PtyStreamCoalescer(bytesThreshold: 4, timeThreshold: 1, idleCeiling: 10)
        coalescer.append(Data([1, 2, 3, 4, 5]), at: zero)
        let chunks = coalescer.drainReadyChunks(at: zero)
        #expect(chunks == [Data([1, 2, 3, 4])])
        // Residual byte 5 stays buffered until next trigger.
        #expect(coalescer.pendingByteCount == 1)
        // Time elapses → flushes the residual.
        let later = coalescer.drainReadyChunks(at: zero.addingTimeInterval(2))
        #expect(later == [Data([5])])
    }

    @Test("Time threshold flushes after coalesceTimeMax has elapsed")
    func flushesWhenTimeReached() {
        var coalescer = PtyStreamCoalescer(bytesThreshold: 1024, timeThreshold: 0.008, idleCeiling: 0.200)
        coalescer.append(Data([0xAA, 0xBB]), at: zero)
        // 4 ms elapsed — under threshold.
        #expect(coalescer.drainReadyChunks(at: zero.addingTimeInterval(0.004)).isEmpty)
        // 9 ms elapsed — past threshold.
        let chunks = coalescer.drainReadyChunks(at: zero.addingTimeInterval(0.009))
        #expect(chunks == [Data([0xAA, 0xBB])])
        #expect(!coalescer.hasPending)
    }

    @Test("Idle ceiling flushes even when time threshold is huge")
    func idleCeilingFlushesSparseBuffer() {
        var coalescer = PtyStreamCoalescer(bytesThreshold: 1024, timeThreshold: 60, idleCeiling: 0.2)
        coalescer.append(Data([0x55]), at: zero)
        // 100 ms — under both thresholds.
        #expect(coalescer.drainReadyChunks(at: zero.addingTimeInterval(0.100)).isEmpty)
        // 250 ms — past idle ceiling.
        let chunks = coalescer.drainReadyChunks(at: zero.addingTimeInterval(0.250))
        #expect(chunks == [Data([0x55])])
    }

    @Test("drainAll force-flushes regardless of size or time")
    func drainAllFlushesEverything() {
        var coalescer = PtyStreamCoalescer(bytesThreshold: 1024, timeThreshold: 60, idleCeiling: 60)
        coalescer.append(Data([1]), at: zero)
        coalescer.append(Data([2, 3]), at: zero)
        let drained = coalescer.drainAll()
        #expect(drained == Data([1, 2, 3]))
        #expect(!coalescer.hasPending)
    }

    @Test("drainAll on empty buffer returns nil and does not produce a chunk")
    func drainAllEmptyReturnsNil() {
        var coalescer = PtyStreamCoalescer()
        let drained = coalescer.drainAll()
        #expect(drained == nil)
    }

    @Test("Append after drainAll resets the firstByteAt timer")
    func appendAfterDrainResetsTimer() {
        var coalescer = PtyStreamCoalescer(bytesThreshold: 1024, timeThreshold: 0.008, idleCeiling: 60)
        coalescer.append(Data([1, 2]), at: zero)
        _ = coalescer.drainAll()
        // Append fresh bytes 100 ms later. The timer must restart from
        // this new time, not the original `zero`.
        let restart = zero.addingTimeInterval(0.100)
        coalescer.append(Data([3]), at: restart)
        // 5 ms after restart — under threshold (timer NOT 105 ms old).
        #expect(coalescer.drainReadyChunks(at: restart.addingTimeInterval(0.005)).isEmpty)
        // 10 ms after restart — past threshold.
        let chunks = coalescer.drainReadyChunks(at: restart.addingTimeInterval(0.010))
        #expect(chunks == [Data([3])])
    }

    @Test("Empty data append is a no-op (no timer started, no flush triggered)")
    func emptyAppendIsNoop() {
        var coalescer = PtyStreamCoalescer()
        coalescer.append(Data(), at: zero)
        // Even an hour later, an empty buffer never flushes.
        #expect(coalescer.drainReadyChunks(at: zero.addingTimeInterval(3600)).isEmpty)
    }

    @Test("Single huge append splits into multiple bytesThreshold-sized chunks")
    func hugeAppendSplitsAcrossChunks() {
        var coalescer = PtyStreamCoalescer(bytesThreshold: 4, timeThreshold: 1, idleCeiling: 10)
        coalescer.append(Data([1, 2, 3, 4, 5, 6, 7, 8, 9]), at: zero)
        let chunks = coalescer.drainReadyChunks(at: zero)
        #expect(chunks == [Data([1, 2, 3, 4]), Data([5, 6, 7, 8])])
        #expect(coalescer.pendingByteCount == 1)
    }

    @Test("Successive appends after partial flush keep firstByteAt anchor")
    func partialFlushPreservesTimerAnchor() {
        // Critical for byte-fairness: when one append is large enough to
        // emit a chunk but leaves a tail, the residual bytes inherit the
        // *original* arrival time rather than getting a fresh timer.
        // This way the residual flushes on its own age, not on a younger
        // restart, matching the iOS responsiveness contract.
        var coalescer = PtyStreamCoalescer(bytesThreshold: 4, timeThreshold: 0.008, idleCeiling: 60)
        coalescer.append(Data([1, 2, 3, 4, 5]), at: zero)
        // Drain the size-triggered chunk; byte 5 stays.
        _ = coalescer.drainReadyChunks(at: zero)
        #expect(coalescer.pendingByteCount == 1)
        // 9 ms later — past timeThreshold relative to the *original*
        // append time (zero), so the residual must flush.
        let chunks = coalescer.drainReadyChunks(at: zero.addingTimeInterval(0.009))
        #expect(chunks == [Data([5])])
    }
}
