// Live-screen push pipeline. iOS sends `.screenSubscribe { sessionId }`,
// the router starts a per-subscription pulse at `ScreenFramePolicy.pulseInterval`
// that calls `adapter.captureScreen(sessionId:)`, hashes the rendered text,
// and pushes a `.screenFrame` envelope only when the hash differs from
// the last one sent on that subscription. Idle terminals therefore burn
// no bandwidth.
//
// Subscription state lives on the router actor (`screenSubscriptions`,
// `screenLastHash`) so per-channel cleanup happens through the same
// `connectionClosed` hook the existing `replyChannels` use.
//
// Threat model: requires `.authenticated` channel state — same gate as
// `.sessionListRequest` / `.cmdExec`. A stolen device id alone never
// unlocks live screen push because the channel must have rejoined or
// paired first.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+ScreenSubscribe")

extension RemoteEnvelopeRouter {
    /// Validates a `.screenSubscribe` envelope and starts the per-subscription
    /// push pulse. Idempotent on `(channelId, sessionId)` — a duplicate
    /// subscribe replaces the prior pulse so a foreground/background churn
    /// on iOS doesn't multiply tasks.
    func handleScreenSubscribe(envelope: Envelope, replyChannel: any ReplyChannel) async {
        guard case .authenticated = channels[replyChannel.channelId, default: .unauthenticated] else {
            await replyError(.unauthorized, message: "Pair before subscribing to screen frames",
                             origin: envelope, via: replyChannel)
            return
        }
        let request: ScreenSubscribeRequest
        do {
            request = try envelope.decode(ScreenSubscribeRequest.self, codec: codec(for: replyChannel.channelId))
        } catch {
            await replyError(.commandRejected, message: "Bad screenSubscribe payload",
                             origin: envelope, via: replyChannel)
            return
        }
        // Cancel any prior pulse for this (channel, session) before starting a new one.
        if let existing = screenSubscriptions[replyChannel.channelId]?[request.sessionId] {
            existing.cancel()
        }
        // Wipe the prior `renderHash` so the new pulse pushes a frame on
        // its first successful capture even when the terminal looks
        // identical to whatever the previous pulse last sent. Without
        // this, an iOS view re-mount (foreground churn, scenePhase, fast
        // navigation back-and-forth) sits on a blank `latestScreenFrame`
        // because every new tick keeps hitting `priorHash == newHash` and
        // skipping. Deletion is per-(channel,session) so other live
        // subscriptions on the same channel keep their dedupe state.
        screenLastHash[replyChannel.channelId]?.removeValue(forKey: request.sessionId)
        var perSession = screenSubscriptions[replyChannel.channelId, default: [:]]
        let channelId = replyChannel.channelId
        let sessionId = request.sessionId
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await runScreenPulse(channelId: channelId, sessionId: sessionId)
        }
        perSession[request.sessionId] = task
        screenSubscriptions[replyChannel.channelId] = perSession
        logger.info("Screen subscription started: channel=\(replyChannel.channelId) session=\(request.sessionId)")
    }

    /// Cancels one subscription (when `sessionId` is set) or every subscription
    /// on the channel (when `sessionId == nil`). Idempotent — cancelling an
    /// unknown subscription is a no-op so transient duplicate `unsubscribe`
    /// calls don't surface errors.
    func handleScreenUnsubscribe(envelope: Envelope, replyChannel: any ReplyChannel) async {
        guard case .authenticated = channels[replyChannel.channelId, default: .unauthenticated] else {
            await replyError(.unauthorized, message: "Pair before unsubscribing from screen frames",
                             origin: envelope, via: replyChannel)
            return
        }
        let request: ScreenUnsubscribeRequest
        do {
            request = try envelope.decode(ScreenUnsubscribeRequest.self, codec: codec(for: replyChannel.channelId))
        } catch {
            await replyError(.commandRejected, message: "Bad screenUnsubscribe payload",
                             origin: envelope, via: replyChannel)
            return
        }
        if let sessionId = request.sessionId {
            screenSubscriptions[replyChannel.channelId]?[sessionId]?.cancel()
            screenSubscriptions[replyChannel.channelId]?.removeValue(forKey: sessionId)
            screenLastHash[replyChannel.channelId]?.removeValue(forKey: sessionId)
        } else {
            for (_, task) in screenSubscriptions[replyChannel.channelId] ?? [:] {
                task.cancel()
            }
            screenSubscriptions[replyChannel.channelId] = nil
            screenLastHash[replyChannel.channelId] = nil
        }
    }

    /// Cancels every subscription on `channelId`. Called from `connectionClosed`
    /// in the main router file so a dropped channel doesn't keep pushing
    /// frames into a dead reply handle.
    func cancelAllScreenSubscriptions(channelId: UUID) {
        for (_, task) in screenSubscriptions[channelId] ?? [:] {
            task.cancel()
        }
        screenSubscriptions[channelId] = nil
        screenLastHash[channelId] = nil
    }

    /// Per-subscription pulse loop. Captures the visible viewport via the
    /// adapter, skips identical renders by `renderHash`, encodes the frame
    /// with the channel's negotiated codec, and pushes via the persisted
    /// `replyChannels[channelId]`. Sleeps `pulseInterval` between ticks.
    /// Exits cleanly on `Task.cancel` (driven by unsubscribe / channel close).
    func runScreenPulse(channelId: UUID, sessionId: UUID) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: ScreenFramePolicy.pulseInterval)
            } catch is CancellationError {
                // CancellationError is expected — unsubscribe / channel close
                // cancels the pulse task; exit cleanly without surfacing.
                return
            } catch {
                return
            }
            guard let frame = await adapter.captureScreen(sessionId: sessionId) else {
                continue
            }
            let priorHash = screenLastHash[channelId]?[sessionId]
            let newHash = frame.renderHash
            guard priorHash != newHash else { continue }
            guard let channel = replyChannels[channelId] else {
                // Reply channel disappeared mid-pulse (channel closed); stop.
                return
            }
            do {
                let envelope = try Envelope.encode(frame, kind: .screenFrame, codec: codec(for: channelId))
                try await channel.send(envelope)
                screenLastHash[channelId, default: [:]][sessionId] = newHash
            } catch {
                logger.warning(
                    "Screen frame push failed on \(channelId)/\(sessionId): \(error.localizedDescription)"
                )
            }
        }
    }
}
