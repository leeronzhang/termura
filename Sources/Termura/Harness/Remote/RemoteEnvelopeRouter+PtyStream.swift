// Live-PTY-stream push pipeline (W3 of "iOS responsive terminal" wave).
// iOS sends `.ptyStreamSubscribe { sessionId, resumeFromSeq? }`, the
// router asks the adapter for a `PtyByteTap.Subscription`, ships an
// initial `.ptyStreamCheckpoint` keyframe (cold-start basis), and
// then fans coalesced byte chunks out as `.ptyStreamChunk` envelopes
// per `PtyStreamPolicy` (32 KB / 8 ms / 200 ms idle ceiling). A
// parallel `checkpointTask` re-emits a keyframe every 30 s OR every
// 256 chunks (whichever first) so resume / reconnect stays cheap.
//
// Subscription state lives on the router actor (`ptyStreamSubscriptions`)
// so per-channel cleanup happens through the same `connectionClosed`
// hook the existing `replyChannels` use. Mirrors `+ScreenSubscribe.swift`
// in shape; the two paths can run side-by-side (CloudKit clients keep
// using the snapshot pulse, LAN+1.1 clients prefer this stream).
//
// Threat model: same as `+ScreenSubscribe` — `.authenticated` channel
// state is required. A stolen device id alone never unlocks live byte
// push because the channel must have rejoined or paired first.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+PtyStream")

extension RemoteEnvelopeRouter {
    /// Fan-in for the `.ptyStreamSubscribe` / `.ptyStreamUnsubscribe`
    /// pair. The main router's `dispatch(...)` collapses both kinds into
    /// one case to keep its cyclomatic complexity within budget; this
    /// helper splits them back out at the next layer.
    func dispatchPtyStream(envelope: Envelope, replyChannel: any ReplyChannel) async {
        switch envelope.kind {
        case .ptyStreamSubscribe:
            await handlePtyStreamSubscribe(envelope: envelope, replyChannel: replyChannel)
        case .ptyStreamUnsubscribe:
            await handlePtyStreamUnsubscribe(envelope: envelope, replyChannel: replyChannel)
        case .ptyResize:
            await handlePtyResize(envelope: envelope, replyChannel: replyChannel)
        default:
            // Unreachable: the main dispatch only routes the kinds
            // above into this helper. Defensive default keeps the
            // switch exhaustive in case a future case is added.
            break
        }
    }

    /// Validates a `.ptyStreamSubscribe` envelope and starts the per-
    /// subscription pump + checkpoint task. Idempotent on
    /// `(channelId, sessionId)` — a duplicate subscribe replaces the
    /// prior pair so background→foreground churn on iOS doesn't multiply
    /// tasks.
    func handlePtyStreamSubscribe(envelope: Envelope, replyChannel: any ReplyChannel) async {
        guard case .authenticated = channels[replyChannel.channelId, default: .unauthenticated] else {
            await replyError(.unauthorized, message: "Pair before subscribing to PTY stream",
                             origin: envelope, via: replyChannel)
            return
        }
        let request: PtyStreamSubscribeRequest
        do {
            request = try envelope.decode(
                PtyStreamSubscribeRequest.self,
                codec: codec(for: replyChannel.channelId)
            )
        } catch {
            await replyError(.commandRejected, message: "Bad ptyStreamSubscribe payload",
                             origin: envelope, via: replyChannel)
            return
        }

        // Cancel any prior pump+checkpoint pair for this (channel, session)
        // before starting fresh ones.
        cancelPtyStreamSubscription(channelId: replyChannel.channelId, sessionId: request.sessionId)

        guard let subscription = await adapter.subscribePty(sessionId: request.sessionId) else {
            await replyError(.sessionNotFound,
                             message: "Session has no live engine",
                             origin: envelope, via: replyChannel)
            return
        }

        await primeResumeOrColdStart(
            channelId: replyChannel.channelId,
            sessionId: request.sessionId,
            resumeFromSeq: request.resumeFromSeq
        )

        // Spawn pump + checkpoint tasks. Both have explicit OWNER (this
        // actor) and TEARDOWN (handlePtyStreamUnsubscribe + connectionClosed).
        let channelId = replyChannel.channelId
        let sessionId = request.sessionId
        let pumpTask: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await runPtyStreamPump(
                channelId: channelId,
                sessionId: sessionId,
                subscription: subscription
            )
        }
        let checkpointTask: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await runPtyStreamCheckpointScheduler(channelId: channelId, sessionId: sessionId)
        }

        var perSession = ptyStreamSubscriptions[channelId, default: [:]]
        perSession[sessionId] = PtyStreamSubscriptionEntry(
            subscriptionId: subscription.id,
            pumpTask: pumpTask,
            checkpointTask: checkpointTask
        )
        ptyStreamSubscriptions[channelId] = perSession
        logger.info("PTY stream subscription started: channel=\(channelId) session=\(sessionId)")
    }

    /// Cancels one PTY subscription (when `sessionId` is set) or every
    /// PTY subscription on the channel (when `sessionId == nil`).
    /// Idempotent — cancelling an unknown subscription is a no-op so
    /// transient duplicate `unsubscribe` calls don't surface errors.
    func handlePtyStreamUnsubscribe(envelope: Envelope, replyChannel: any ReplyChannel) async {
        guard case .authenticated = channels[replyChannel.channelId, default: .unauthenticated] else {
            await replyError(.unauthorized, message: "Pair before unsubscribing from PTY stream",
                             origin: envelope, via: replyChannel)
            return
        }
        let request: PtyStreamUnsubscribeRequest
        do {
            request = try envelope.decode(
                PtyStreamUnsubscribeRequest.self,
                codec: codec(for: replyChannel.channelId)
            )
        } catch {
            await replyError(.commandRejected, message: "Bad ptyStreamUnsubscribe payload",
                             origin: envelope, via: replyChannel)
            return
        }
        if let sessionId = request.sessionId {
            await tearDownPtyStreamSubscription(channelId: replyChannel.channelId, sessionId: sessionId)
        } else {
            await cancelAllPtyStreamSubscriptions(channelId: replyChannel.channelId)
        }
    }

    /// Cancels every PTY subscription on `channelId`. Called from
    /// `connectionClosed` in the main router file so a dropped channel
    /// doesn't keep streaming bytes into a dead reply handle.
    func cancelAllPtyStreamSubscriptions(channelId: UUID) async {
        let entries = ptyStreamSubscriptions[channelId] ?? [:]
        ptyStreamSubscriptions[channelId] = nil
        // W5 — drop the resume ring + seq counters too. A dead channel
        // can never resume; a fresh pair starts a new ring at seq 0.
        ptyResumeBuffers[channelId] = nil
        ptyStreamSeq[channelId] = nil
        for (sessionId, entry) in entries {
            entry.pumpTask.cancel()
            entry.checkpointTask.cancel()
            await adapter.unsubscribePty(sessionId: sessionId, subscriptionId: entry.subscriptionId)
        }
    }

    /// Per-subscription byte pump. Drains the adapter-supplied
    /// `Subscription.stream`, feeds the coalescer, and ships every
    /// ready chunk as a `.ptyStreamChunk` envelope. Exits cleanly when
    /// the stream finishes (engine.terminate / tap.finishAll) or on
    /// `Task.cancel` (unsubscribe / channel close).
    func runPtyStreamPump(
        channelId: UUID,
        sessionId: UUID,
        subscription: PtyByteTap.Subscription
    ) async {
        var coalescer = PtyStreamCoalescer()
        for await data in subscription.stream {
            if Task.isCancelled { break }
            let now = clock()
            coalescer.append(data, at: now)
            for chunk in coalescer.drainReadyChunks(at: now) {
                await shipChunk(channelId: channelId, sessionId: sessionId, payload: chunk)
            }
        }
        // Stream finished (engine torn down, or cancellation observed
        // before the next iteration). Flush any buffered tail so iOS
        // doesn't lose the last few bytes.
        if let tail = coalescer.drainAll() {
            await shipChunk(channelId: channelId, sessionId: sessionId, payload: tail)
        }
    }

    /// Background scheduler that emits a fresh `.ptyStreamCheckpoint`
    /// every `PtyStreamPolicy.checkpointEvery` (30 s default). Counts
    /// of chunks per session are not currently tracked here — the
    /// 30 s wall-clock cadence is the single resync trigger; `+Resume`
    /// (W5) will tighten this with a chunk-count override.
    func runPtyStreamCheckpointScheduler(channelId: UUID, sessionId: UUID) async {
        var seq: UInt64 = 1
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: PtyStreamPolicy.checkpointEvery)
            } catch is CancellationError {
                // CancellationError is expected — unsubscribe / channel
                // close cancels the scheduler task; exit cleanly without
                // surfacing.
                return
            } catch {
                return
            }
            await shipCheckpoint(channelId: channelId, sessionId: sessionId, seq: seq)
            seq &+= 1
        }
    }
}
