// Pure-function coalescing state machine for the PTY byte-stream pump.
// The router calls `append(_:at:)` whenever new bytes arrive from the
// `PtyByteTap.Subscription` stream, then `drainReadyChunks(at:)` on
// every loop tick (or after each append) to pull out any chunks ready
// to ship as `.ptyStreamChunk` envelopes. `drainAll()` is called when
// the upstream subscription finishes so the last in-flight buffer
// doesn't sit unflushed.
//
// All time is passed in by the caller (`now: Date`) so tests stay
// deterministic without hooking into a Clock or sleeping.
//
// Flush triggers (whichever first):
// - **Size**: `bytesThreshold` (default 32 KB) reached.
// - **Time**: `now - firstByteAt >= timeThreshold` (default 8 ms).
// - **Idle**: `now - firstByteAt >= idleCeiling` (default 200 ms) — guarantees
//   the very last byte of an idle stream still ships even if the size
//   threshold was never reached.
// - **Drain**: caller invokes `drainAll()`.
//
// Why these numbers: 8 ms keeps end-to-end input latency under the 16 ms
// terminal-input SLO (§7.2). 32 KB caps any single envelope payload so a
// large `cat` doesn't bloat one WebSocket frame. 200 ms idle ceiling
// guarantees responsiveness for sparse interactive prompts.

import Foundation
import TermuraRemoteProtocol

struct PtyStreamCoalescer: Sendable {
    let bytesThreshold: Int
    let timeThreshold: TimeInterval
    let idleCeiling: TimeInterval

    private var buffer: Data = .init()
    private var firstByteAt: Date?

    init(
        bytesThreshold: Int = PtyStreamPolicy.coalesceBytesMax,
        timeThreshold: TimeInterval = 0.008,
        idleCeiling: TimeInterval = 0.200
    ) {
        self.bytesThreshold = bytesThreshold
        self.timeThreshold = timeThreshold
        self.idleCeiling = idleCeiling
    }

    /// True when there are pending bytes to ship eventually. Used by the
    /// router pump's idle-tick path to decide whether to call
    /// `drainReadyChunks(at:)` or skip.
    var hasPending: Bool { !buffer.isEmpty }

    /// Bytes currently held in the coalescer (waiting on a flush trigger).
    /// Useful for diagnostics / metrics; not on the hot path.
    var pendingByteCount: Int { buffer.count }

    /// Append new bytes. The wall-clock time the bytes arrived is captured
    /// so subsequent `drainReadyChunks(at:)` calls can decide whether
    /// `timeThreshold` or `idleCeiling` has elapsed.
    mutating func append(_ data: Data, at now: Date) {
        guard !data.isEmpty else { return }
        if firstByteAt == nil { firstByteAt = now }
        buffer.append(data)
    }

    /// Drain every chunk that is ready to ship at `now`. Returns 0..N
    /// payload byte arrays; the caller wraps each into a
    /// `PtyStreamChunk` envelope with the next monotonic `seq`.
    ///
    /// Sized so that no returned payload exceeds `bytesThreshold` — a
    /// single very large `append` is split into multiple chunks if
    /// needed.
    mutating func drainReadyChunks(at now: Date) -> [Data] {
        var chunks: [Data] = []
        while shouldFlush(at: now) {
            chunks.append(takeChunk())
        }
        return chunks
    }

    /// Force-drain everything currently held, regardless of size or time
    /// thresholds. Used at the end of the pump loop when the upstream
    /// subscription stream has finished — flush rather than let bytes
    /// die in the buffer.
    mutating func drainAll() -> Data? {
        guard !buffer.isEmpty else { return nil }
        defer {
            buffer.removeAll(keepingCapacity: false)
            firstByteAt = nil
        }
        return buffer
    }

    private func shouldFlush(at now: Date) -> Bool {
        guard !buffer.isEmpty else { return false }
        if buffer.count >= bytesThreshold { return true }
        guard let first = firstByteAt else { return false }
        let elapsed = now.timeIntervalSince(first)
        return elapsed >= timeThreshold || elapsed >= idleCeiling
    }

    private mutating func takeChunk() -> Data {
        let take = min(buffer.count, bytesThreshold)
        let chunk = buffer.prefix(take)
        buffer.removeFirst(take)
        // Reset firstByteAt only when the buffer is fully drained — otherwise
        // residual bytes from the same arrival group keep their original
        // age toward the time / idle thresholds.
        if buffer.isEmpty { firstByteAt = nil }
        return Data(chunk)
    }
}
