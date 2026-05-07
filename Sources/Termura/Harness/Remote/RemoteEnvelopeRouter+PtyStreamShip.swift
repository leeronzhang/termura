// PTY-stream shipping helpers + per-subscription bookkeeping struct
// split out of `RemoteEnvelopeRouter+PtyStream.swift` so that file
// stays under the file_length budget. The actor's `replyChannels`,
// `ptyStreamSeq`, `ptyResumeBuffers`, `ptyStreamSubscriptions`,
// `clock`, `adapter`, `codec(for:)` are module-internal so this
// same-module extension can ship envelopes without going through a
// public-actor hop.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+PtyStreamShip")

extension RemoteEnvelopeRouter {
    func shipChunk(channelId: UUID, sessionId: UUID, payload: Data) async {
        guard let channel = replyChannels[channelId] else { return }
        let seq = nextPtyStreamSeq(channelId: channelId, sessionId: sessionId)
        let chunk = PtyStreamChunk(
            sessionId: sessionId,
            seq: seq,
            payload: payload,
            producedAt: clock()
        )
        do {
            let envelope = try Envelope.encode(chunk, kind: .ptyStreamChunk, codec: codec(for: channelId))
            try await channel.send(envelope)
            // W5 — record into the resume ring AFTER the network send
            // so a failed send doesn't pollute the replay buffer.
            ptyResumeBuffers[channelId, default: [:]][sessionId, default: PtyResumeRing()]
                .append(seq: seq, payload: payload)
        } catch {
            logger.warning(
                "PTY chunk push failed on \(channelId)/\(sessionId): \(error.localizedDescription)"
            )
        }
    }

    func shipCheckpoint(channelId: UUID, sessionId: UUID, seq: UInt64) async {
        guard let channel = replyChannels[channelId] else { return }
        guard let checkpoint = await adapter.currentCheckpoint(sessionId: sessionId, seq: seq) else {
            // Engine has no live surface yet — skip this keyframe; the
            // 30 s scheduler will retry on the next tick.
            return
        }
        do {
            let envelope = try Envelope.encode(
                checkpoint,
                kind: .ptyStreamCheckpoint,
                codec: codec(for: channelId)
            )
            try await channel.send(envelope)
        } catch {
            logger.warning(
                "PTY checkpoint push failed on \(channelId)/\(sessionId): \(error.localizedDescription)"
            )
        }
    }

    /// Issues the next monotonic chunk seq for `(channel, session)`,
    /// starting at 1 so the cold-start checkpoint at seq 0 has a
    /// guaranteed lower-numbered slot. Wraps via `&+=` after `UInt64.max`
    /// — practically unreachable but defined behaviour rather than a
    /// crash.
    func nextPtyStreamSeq(channelId: UUID, sessionId: UUID) -> UInt64 {
        var perSession = ptyStreamSeq[channelId, default: [:]]
        let next = (perSession[sessionId] ?? 0) &+ 1
        perSession[sessionId] = next
        ptyStreamSeq[channelId] = perSession
        return next
    }

    func cancelPtyStreamSubscription(channelId: UUID, sessionId: UUID) {
        guard let entry = ptyStreamSubscriptions[channelId]?[sessionId] else { return }
        entry.pumpTask.cancel()
        entry.checkpointTask.cancel()
        ptyStreamSubscriptions[channelId]?.removeValue(forKey: sessionId)
    }

    func tearDownPtyStreamSubscription(channelId: UUID, sessionId: UUID) async {
        guard let entry = ptyStreamSubscriptions[channelId]?[sessionId] else { return }
        entry.pumpTask.cancel()
        entry.checkpointTask.cancel()
        ptyStreamSubscriptions[channelId]?.removeValue(forKey: sessionId)
        ptyStreamSeq[channelId]?.removeValue(forKey: sessionId)
        // W5 — drop the per-session ring too; a re-subscribe will
        // either start fresh or replay against a brand-new ring.
        ptyResumeBuffers[channelId]?.removeValue(forKey: sessionId)
        await adapter.unsubscribePty(sessionId: sessionId, subscriptionId: entry.subscriptionId)
    }
}

/// Stored on `RemoteEnvelopeRouter.ptyStreamSubscriptions[channelId][sessionId]`
/// so the actor can cancel both background tasks and tell the adapter to
/// release the underlying tap subscription on tear-down.
struct PtyStreamSubscriptionEntry: Sendable {
    let subscriptionId: UUID
    let pumpTask: Task<Void, Never>
    let checkpointTask: Task<Void, Never>
}
