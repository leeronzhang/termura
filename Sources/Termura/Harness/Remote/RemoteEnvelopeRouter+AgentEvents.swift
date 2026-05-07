// Wave 8 — agent-conversation event push pipeline.
//
// iOS sends `.agentEventSubscribe { sessionId, sinceEventId? }`,
// the router asks the adapter for an `AgentEventSubscription`,
// ships its `AgentEventCheckpoint` as the cold-start basis, then
// fans subsequent events out as `.agentEvent` envelopes via a
// per-subscription pump task.
//
// Subscription state lives on the router actor
// (`agentEventSubscriptions`) so per-channel cleanup happens through
// the same `connectionClosed` hook the existing `replyChannels` use.
// Mirrors `+PtyStream.swift` in shape; the two paths run side-by-side
// — agent events are the new default for iOS, PTY stream stays as a
// Debug fallback.
//
// Threat model: same as `+PtyStream` — `.authenticated` channel
// state required.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+AgentEvents")

extension RemoteEnvelopeRouter {
    /// Top-level fan-in for every subscription-style envelope. The
    /// main `dispatch(...)` collapses PTY + agent kinds into one case
    /// to stay under cyclomatic_complexity 15; this helper routes
    /// each kind to its per-feature handler.
    func dispatchSubscriptionEnvelope(
        envelope: Envelope,
        replyChannel: any ReplyChannel
    ) async {
        switch envelope.kind {
        case .ptyStreamSubscribe, .ptyStreamUnsubscribe, .ptyResize:
            await dispatchPtyStream(envelope: envelope, replyChannel: replyChannel)
        case .agentEventSubscribe:
            await handleAgentEventSubscribe(envelope: envelope, replyChannel: replyChannel)
        case .agentEventUnsubscribe:
            await handleAgentEventUnsubscribe(envelope: envelope, replyChannel: replyChannel)
        default:
            break
        }
    }

    func handleAgentEventSubscribe(envelope: Envelope, replyChannel: any ReplyChannel) async {
        guard case .authenticated = channels[replyChannel.channelId, default: .unauthenticated] else {
            await replyError(.unauthorized, message: "Pair before subscribing to agent events",
                             origin: envelope, via: replyChannel)
            return
        }
        let request: AgentEventSubscribeRequest
        do {
            request = try envelope.decode(
                AgentEventSubscribeRequest.self,
                codec: codec(for: replyChannel.channelId)
            )
        } catch {
            await replyError(.commandRejected, message: "Bad agentEventSubscribe payload",
                             origin: envelope, via: replyChannel)
            return
        }

        cancelAgentEventSubscription(channelId: replyChannel.channelId, sessionId: request.sessionId)

        guard let subscription = await adapter.subscribeAgentEvents(
            sessionId: request.sessionId,
            sinceEventId: request.sinceEventId
        ) else {
            // No transcript / no live source — degrade silently. iOS
            // can fall back to the PTY stream path; surfacing an
            // error here would also tear down the connection in
            // some clients which is too aggressive for this case.
            logger.info("Agent subscribe: no source for session \(request.sessionId)")
            return
        }

        await shipAgentEventCheckpoint(
            channelId: replyChannel.channelId,
            checkpoint: subscription.checkpoint
        )

        let channelId = replyChannel.channelId
        let sessionId = request.sessionId
        let stream = subscription.stream
        let pumpTask: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await runAgentEventPump(channelId: channelId, sessionId: sessionId, stream: stream)
        }
        var perSession = agentEventSubscriptions[channelId, default: [:]]
        perSession[sessionId] = AgentEventSubscriptionEntry(
            subscriptionId: subscription.id,
            pumpTask: pumpTask
        )
        agentEventSubscriptions[channelId] = perSession
        logger.info("Agent event subscription started: channel=\(channelId) session=\(sessionId)")
    }

    func handleAgentEventUnsubscribe(envelope: Envelope, replyChannel: any ReplyChannel) async {
        guard case .authenticated = channels[replyChannel.channelId, default: .unauthenticated] else {
            await replyError(.unauthorized, message: "Pair before unsubscribing from agent events",
                             origin: envelope, via: replyChannel)
            return
        }
        let request: AgentEventUnsubscribeRequest
        do {
            request = try envelope.decode(
                AgentEventUnsubscribeRequest.self,
                codec: codec(for: replyChannel.channelId)
            )
        } catch {
            await replyError(.commandRejected, message: "Bad agentEventUnsubscribe payload",
                             origin: envelope, via: replyChannel)
            return
        }
        if let sessionId = request.sessionId {
            await tearDownAgentEventSubscription(
                channelId: replyChannel.channelId,
                sessionId: sessionId
            )
        } else {
            await cancelAllAgentEventSubscriptions(channelId: replyChannel.channelId)
        }
    }

    /// Cancels every agent-event subscription on `channelId`. Called
    /// from `connectionClosed` so a dropped channel doesn't keep
    /// pumping events to a dead reply handle.
    func cancelAllAgentEventSubscriptions(channelId: UUID) async {
        let entries = agentEventSubscriptions[channelId] ?? [:]
        agentEventSubscriptions[channelId] = nil
        agentEventSeq[channelId] = nil
        for (sessionId, entry) in entries {
            entry.pumpTask.cancel()
            await adapter.unsubscribeAgentEvents(
                sessionId: sessionId,
                subscriptionId: entry.subscriptionId
            )
        }
    }

    /// Per-subscription event pump. Drains the source's
    /// `AsyncStream<AgentEvent>` and ships each event as an
    /// `.agentEvent` envelope. Exits cleanly when the stream
    /// finishes (source teardown) or on `Task.cancel` (unsubscribe
    /// / channel close).
    func runAgentEventPump(
        channelId: UUID,
        sessionId: UUID,
        stream: AsyncStream<AgentEvent>
    ) async {
        for await event in stream {
            if Task.isCancelled { break }
            await shipAgentEvent(channelId: channelId, sessionId: sessionId, event: event)
        }
    }

    // MARK: - Helpers

    private func shipAgentEvent(channelId: UUID, sessionId: UUID, event: AgentEvent) async {
        guard let channel = replyChannels[channelId] else { return }
        // Stamp the wire seq independently from the source's seq so
        // gap detection is accurate per-channel even if the source
        // restarts its counter on a new subscribe.
        let seq = nextAgentEventSeq(channelId: channelId, sessionId: sessionId)
        let stamped = AgentEvent(
            id: event.id,
            sessionId: event.sessionId,
            seq: seq,
            producedAt: event.producedAt,
            payload: event.payload
        )
        do {
            let envelope = try Envelope.encode(stamped, kind: .agentEvent, codec: codec(for: channelId))
            try await channel.send(envelope)
        } catch {
            logger.warning(
                "Agent event push failed on \(channelId)/\(sessionId): \(error.localizedDescription)"
            )
        }
    }

    private func shipAgentEventCheckpoint(
        channelId: UUID,
        checkpoint: AgentEventCheckpoint
    ) async {
        guard let channel = replyChannels[channelId] else { return }
        do {
            let envelope = try Envelope.encode(
                checkpoint,
                kind: .agentEventCheckpoint,
                codec: codec(for: channelId)
            )
            try await channel.send(envelope)
        } catch {
            logger.warning(
                "Agent checkpoint push failed on \(channelId): \(error.localizedDescription)"
            )
        }
    }

    private func nextAgentEventSeq(channelId: UUID, sessionId: UUID) -> UInt64 {
        var perSession = agentEventSeq[channelId, default: [:]]
        let next = (perSession[sessionId] ?? 0) &+ 1
        perSession[sessionId] = next
        agentEventSeq[channelId] = perSession
        return next
    }

    private func cancelAgentEventSubscription(channelId: UUID, sessionId: UUID) {
        guard let entry = agentEventSubscriptions[channelId]?[sessionId] else { return }
        entry.pumpTask.cancel()
        agentEventSubscriptions[channelId]?.removeValue(forKey: sessionId)
    }

    private func tearDownAgentEventSubscription(channelId: UUID, sessionId: UUID) async {
        guard let entry = agentEventSubscriptions[channelId]?[sessionId] else { return }
        entry.pumpTask.cancel()
        agentEventSubscriptions[channelId]?.removeValue(forKey: sessionId)
        agentEventSeq[channelId]?.removeValue(forKey: sessionId)
        await adapter.unsubscribeAgentEvents(
            sessionId: sessionId,
            subscriptionId: entry.subscriptionId
        )
    }
}

/// Stored on `RemoteEnvelopeRouter.agentEventSubscriptions[channelId][sessionId]`
/// so the actor can cancel the pump task and tell the adapter to
/// release the upstream subscription on tear-down.
struct AgentEventSubscriptionEntry: Sendable {
    let subscriptionId: UUID
    let pumpTask: Task<Void, Never>
}
