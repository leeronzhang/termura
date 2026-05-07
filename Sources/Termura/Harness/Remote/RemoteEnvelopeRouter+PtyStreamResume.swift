// W5 — resume / replay path for the PTY-stream pipeline. Lives in its
// own extension file so the main `+PtyStream.swift` can stay under
// the file_length budget. The router calls `tryReplayForResume(...)`
// from `handlePtyStreamSubscribe` when the incoming subscribe carries
// a `resumeFromSeq`; this helper consults the per-session
// `PtyResumeRing`, replays whatever chunks are still buffered past
// that seq, and reports whether the cold-start checkpoint can be
// skipped.
//
// Falls back to a fresh checkpoint when:
// 1. No `resumeFromSeq` was provided (cold start, default path).
// 2. No ring exists for `(channelId, sessionId)` — first subscribe
//    on this channel.
// 3. Ring's oldest seq is newer than `resumeFromSeq + 1` — gap is
//    too large for the 8 KB buffer; client missed too much.
// 4. Ring is exhausted at-or-before `resumeFromSeq` — client raced
//    past the highest shipped chunk.
// 5. Network send fails partway through — partial replay is dangerous
//    (engine sees only some bytes), so we fall through to a fresh
//    checkpoint to re-anchor.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+PtyStreamResume")

extension RemoteEnvelopeRouter {
    /// Decide between replaying from the ring (resume path) and
    /// shipping a fresh `.ptyStreamCheckpoint` (cold-start). Centralises
    /// the ring-reset + seq-reset bookkeeping so the subscribe handler
    /// stays under its function-body budget.
    func primeResumeOrColdStart(
        channelId: UUID,
        sessionId: UUID,
        resumeFromSeq: UInt64?
    ) async {
        let replayed = await tryReplayForResume(
            channelId: channelId,
            sessionId: sessionId,
            resumeFromSeq: resumeFromSeq
        )
        guard !replayed else { return }
        // Cold-start (or resume-too-old): reset ring + seq, ship
        // checkpoint at seq 0 so the iOS engine re-anchors.
        ptyResumeBuffers[channelId, default: [:]][sessionId] = PtyResumeRing()
        ptyStreamSeq[channelId, default: [:]][sessionId] = 0
        await shipCheckpoint(channelId: channelId, sessionId: sessionId, seq: 0)
    }

    /// Try to honour `resumeFromSeq` by replaying chunks from the ring.
    /// Returns `true` when the replay completed (caller skips the
    /// cold-start checkpoint); `false` when the caller must ship a
    /// fresh checkpoint.
    func tryReplayForResume(
        channelId: UUID,
        sessionId: UUID,
        resumeFromSeq: UInt64?
    ) async -> Bool {
        guard let resumeFromSeq else { return false }
        guard let ring = ptyResumeBuffers[channelId]?[sessionId] else { return false }
        guard ring.canResume(from: resumeFromSeq) else { return false }
        let chunks = ring.chunksAfter(seq: resumeFromSeq)
        guard !chunks.isEmpty else { return false }
        guard let channel = replyChannels[channelId] else { return false }
        for entry in chunks {
            let chunk = PtyStreamChunk(
                sessionId: sessionId,
                seq: entry.seq,
                payload: entry.payload,
                producedAt: clock()
            )
            do {
                let envelope = try Envelope.encode(
                    chunk,
                    kind: .ptyStreamChunk,
                    codec: codec(for: channelId)
                )
                try await channel.send(envelope)
            } catch {
                logger.warning(
                    "PTY resume replay failed on \(channelId)/\(sessionId): \(error.localizedDescription)"
                )
                return false
            }
        }
        return true
    }
}
