// W5 — bounded byte ring of recently-shipped `PtyStreamChunk` entries
// per `(channelId, sessionId)`. The router writes every chunk into the
// ring as it ships; on a resume-`.ptyStreamSubscribe` (carrying a
// `resumeFromSeq`) the router walks the ring forward from that seq
// and re-ships everything still buffered, sparing the iOS client from
// re-feeding from a fresh checkpoint when the gap is small.
//
// Sized at 8 KB total payload to bound memory across long-lived
// channels: enough to cover ~1.5 s of vim/htop-class redraw activity
// at the 32 KB/8 ms coalescer cadence (chunks usually well under 8 KB
// each), while still hitting hard memory ceilings on iPad with
// dozens of simultaneous sessions.
//
// Pure value type, no concurrency primitives — the router actor owns
// the rings via `ptyResumeBuffers` and serializes access for free.

import Foundation
import TermuraRemoteProtocol

struct PtyResumeRing: Sendable {
    /// Maximum total payload bytes held across all entries. Newest
    /// chunks evict oldest until the buffer fits within this budget.
    static let defaultByteBudget: Int = 8 * 1024

    private struct Entry: Sendable {
        let seq: UInt64
        let payload: Data
    }

    private var entries: [Entry] = []
    private var totalBytes: Int = 0
    let byteBudget: Int

    init(byteBudget: Int = PtyResumeRing.defaultByteBudget) {
        self.byteBudget = byteBudget
    }

    /// Whether the ring has any buffered chunk. `false` immediately
    /// after a fresh `.ptyStreamSubscribe` (router hasn't shipped yet).
    var isEmpty: Bool { entries.isEmpty }

    /// Lowest seq still buffered, or `nil` when empty. Used by the
    /// resume path to decide whether `resumeFromSeq` is reachable.
    var minSeq: UInt64? { entries.first?.seq }

    /// Highest seq still buffered, or `nil` when empty. Used by the
    /// resume path to decide whether the requested resume point is
    /// already past every cached entry (rare but possible if the
    /// client raced ahead of its own state).
    var maxSeq: UInt64? { entries.last?.seq }

    /// Total payload bytes currently held. Helpful for diagnostics
    /// and metrics; not on the hot path.
    var bufferedByteCount: Int { totalBytes }

    /// Append a freshly-shipped chunk. Caller must invoke this in
    /// strict seq-monotonic order; the ring assumes monotonicity to
    /// keep `entries` sorted without an extra pass.
    mutating func append(seq: UInt64, payload: Data) {
        entries.append(Entry(seq: seq, payload: payload))
        totalBytes += payload.count
        evictUntilUnderBudget()
    }

    /// Walk forward from `resumeFromSeq` and return every chunk
    /// strictly newer than that seq, in order. Empty if either the
    /// ring no longer holds anything past `resumeFromSeq` (router
    /// must fall back to a fresh checkpoint) or the requested point
    /// is already past `maxSeq` (client raced ahead — also fall back
    /// to fresh checkpoint to avoid silent state divergence).
    func chunksAfter(seq resumeFromSeq: UInt64) -> [(seq: UInt64, payload: Data)] {
        // Optimised early exits.
        guard !entries.isEmpty else { return [] }
        if let max = maxSeq, max <= resumeFromSeq { return [] }
        // Linear walk — at 8 KB / typical 1-4 KB chunks, the array is
        // O(2-8) entries; binary search wouldn't recoup its overhead.
        var result: [(seq: UInt64, payload: Data)] = []
        for entry in entries where entry.seq > resumeFromSeq {
            result.append((entry.seq, entry.payload))
        }
        return result
    }

    /// `true` when the ring still holds chunks at or before
    /// `resumeFromSeq`, i.e. resume is reachable. Returns `false` if
    /// the oldest cached entry is already newer than the resume point
    /// — in that case the client missed too many chunks and the
    /// router must ship a fresh checkpoint instead.
    func canResume(from resumeFromSeq: UInt64) -> Bool {
        guard let min = minSeq else { return false }
        return min <= resumeFromSeq + 1
    }

    private mutating func evictUntilUnderBudget() {
        // Keep at least the newest entry so a single oversized chunk
        // doesn't leave the ring empty after `append`. Caller is
        // responsible for picking a reasonable budget; "newest stays"
        // is the documented contract.
        while totalBytes > byteBudget, entries.count > 1 {
            let oldest = entries.removeFirst()
            totalBytes -= oldest.payload.count
        }
    }
}
