import Foundation
@testable import Termura
import Testing

@Suite("PtyResumeRing")
struct PtyResumeRingTests {
    @Test("Empty ring reports nothing buffered")
    func emptyRing() {
        let ring = PtyResumeRing()
        #expect(ring.isEmpty)
        #expect(ring.minSeq == nil)
        #expect(ring.maxSeq == nil)
        #expect(ring.bufferedByteCount == 0)
        #expect(ring.chunksAfter(seq: 0).isEmpty)
        #expect(!ring.canResume(from: 0))
    }

    @Test("Append within budget retains every entry")
    func appendWithinBudget() {
        var ring = PtyResumeRing(byteBudget: 1000)
        ring.append(seq: 1, payload: Data(repeating: 0x41, count: 100))
        ring.append(seq: 2, payload: Data(repeating: 0x42, count: 200))
        ring.append(seq: 3, payload: Data(repeating: 0x43, count: 300))
        #expect(ring.minSeq == 1)
        #expect(ring.maxSeq == 3)
        #expect(ring.bufferedByteCount == 600)
    }

    @Test("Append over budget evicts oldest entries first")
    func appendOverBudgetEvictsOldest() {
        var ring = PtyResumeRing(byteBudget: 500)
        ring.append(seq: 1, payload: Data(repeating: 0xAA, count: 200))
        ring.append(seq: 2, payload: Data(repeating: 0xBB, count: 200))
        ring.append(seq: 3, payload: Data(repeating: 0xCC, count: 200))
        // Total 600 > 500 budget — oldest (seq 1) evicted.
        #expect(ring.minSeq == 2)
        #expect(ring.maxSeq == 3)
        #expect(ring.bufferedByteCount == 400)
    }

    @Test("chunksAfter returns only entries strictly newer than seq")
    func chunksAfterFiltersStrict() {
        var ring = PtyResumeRing()
        ring.append(seq: 1, payload: Data([0x01]))
        ring.append(seq: 2, payload: Data([0x02]))
        ring.append(seq: 3, payload: Data([0x03]))
        let after1 = ring.chunksAfter(seq: 1)
        #expect(after1.map(\.seq) == [2, 3])
        // resumeFromSeq == maxSeq means client is up-to-date — return empty.
        let after3 = ring.chunksAfter(seq: 3)
        #expect(after3.isEmpty)
        // resumeFromSeq below minSeq returns everything (degenerate but
        // safe — caller decides based on `canResume(from:)`).
        let after0 = ring.chunksAfter(seq: 0)
        #expect(after0.map(\.seq) == [1, 2, 3])
    }

    @Test("canResume reports reachability of the requested resume point")
    func canResumeReachability() {
        var ring = PtyResumeRing()
        ring.append(seq: 5, payload: Data([0x05]))
        ring.append(seq: 6, payload: Data([0x06]))
        ring.append(seq: 7, payload: Data([0x07]))
        // resumeFromSeq 4 → minSeq 5 ≤ 4+1 → reachable (replay 5,6,7).
        #expect(ring.canResume(from: 4))
        // resumeFromSeq 3 → minSeq 5 > 3+1 → too old, fall back to checkpoint.
        #expect(!ring.canResume(from: 3))
        // resumeFromSeq 7 → minSeq 5 ≤ 8 → reachable (replay nothing).
        #expect(ring.canResume(from: 7))
    }

    @Test("Custom budget honoured (degenerate small budget evicts immediately)")
    func customBudgetSmall() {
        var ring = PtyResumeRing(byteBudget: 50)
        ring.append(seq: 1, payload: Data(repeating: 0x00, count: 100))
        // Single oversized chunk — eviction loop runs once and the
        // ring keeps the latest entry even though it exceeds the
        // budget. (Caller is responsible for picking a reasonable
        // budget; the ring's contract is "newest stays".)
        #expect(ring.maxSeq == 1)
    }

    @Test("Eviction preserves seq monotonicity")
    func evictionPreservesMonotonicity() {
        var ring = PtyResumeRing(byteBudget: 300)
        for seq in (1 ... 10).map(UInt64.init) {
            ring.append(seq: seq, payload: Data(repeating: UInt8(seq), count: 100))
        }
        // 1000 bytes pushed, budget 300 → only the newest 3 entries
        // remain (seqs 8, 9, 10).
        let chunks = ring.chunksAfter(seq: 0)
        #expect(chunks.map(\.seq) == [8, 9, 10])
    }
}
