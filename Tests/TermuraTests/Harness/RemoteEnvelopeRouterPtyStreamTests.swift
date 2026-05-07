import Foundation
@testable import Termura
import TermuraRemoteProtocol
@testable import TermuraRemoteServer
import Testing

/// W3 — exercises `RemoteEnvelopeRouter`'s `.ptyStreamSubscribe` /
/// `.ptyStreamUnsubscribe` handlers and the per-channel cleanup wiring.
/// Tests focus on the synchronous reject / accept paths plus subscription
/// lifecycle (duplicate-subscribe, unsubscribe, connectionClosed). The
/// push path itself (chunks shipped via `replyChannels[channelId]`) is
/// not exercised here because that channel slot is only populated by
/// the real pair handshake; W4 covers it via end-to-end LAN tests.
///
/// Helpers (`PtyStreamRecordingReplyChannel`, `PtyStreamStubAdapter`,
/// `PtyStreamRouterFactory`) live in `PtyStreamRouterTestHelpers.swift`
/// so this file stays under the file-length budget.
@Suite("RemoteEnvelopeRouter.ptyStream handlers")
struct RemoteEnvelopeRouterPtyStreamTests {
    @Test("Unauthenticated subscribe returns unauthorized error")
    func unauthenticatedSubscribeIsRejected() async throws {
        let adapter = PtyStreamStubAdapter(knownSessionId: UUID())
        let router = PtyStreamRouterFactory.makeRouter(adapter: adapter)
        let channel = PtyStreamRecordingReplyChannel()
        try await router.handle(
            envelope: PtyStreamRouterFactory.subscribeEnvelope(sessionId: UUID()),
            replyChannel: channel
        )
        let replies = await channel.snapshot()
        #expect(replies.count == 1)
        #expect(replies.first?.kind == .error)
    }

    @Test("Authenticated subscribe to unknown session replies sessionNotFound")
    func authenticatedSubscribeUnknownSession() async throws {
        let adapter = PtyStreamStubAdapter(knownSessionId: UUID())
        let router = PtyStreamRouterFactory.makeRouter(adapter: adapter)
        let channel = PtyStreamRecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: UUID(),
            negotiatedCodec: .json
        )
        try await router.handle(
            envelope: PtyStreamRouterFactory.subscribeEnvelope(sessionId: UUID()),
            replyChannel: channel
        )
        let replies = await channel.snapshot()
        let envelope = try #require(replies.first)
        let error = try envelope.decode(RemoteError.self, codec: JSONRemoteCodec())
        #expect(error.code == .sessionNotFound)
    }

    @Test("Authenticated subscribe with live engine spawns pump (no sync reply)")
    func authenticatedSubscribeStartsPump() async throws {
        let sessionId = UUID()
        let adapter = PtyStreamStubAdapter(knownSessionId: sessionId)
        // Hand the router a live tap so subscribePty returns non-nil.
        let tap = PtyByteTap()
        await adapter.setNextSubscription(tap.subscribe())

        let router = PtyStreamRouterFactory.makeRouter(adapter: adapter)
        let channel = PtyStreamRecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: UUID(),
            negotiatedCodec: .json
        )
        try await router.handle(
            envelope: PtyStreamRouterFactory.subscribeEnvelope(sessionId: sessionId),
            replyChannel: channel
        )

        // Subscribe is fire-and-forget; the cold-start checkpoint and
        // chunks ship via `replyChannels[channelId]`, which is not set
        // here (no full pair handshake), so the recording channel stays
        // empty. We assert no error envelope came back, then explicitly
        // unsubscribe so the test exits cleanly.
        let replies = await channel.snapshot()
        #expect(replies.isEmpty, "Subscribe must not produce a synchronous reply on success")

        try await router.handle(
            envelope: PtyStreamRouterFactory.unsubscribeEnvelope(sessionId: sessionId),
            replyChannel: channel
        )
        let calls = await adapter.unsubscribeCalls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == sessionId)
    }

    @Test("Duplicate subscribe replaces prior subscription (cancels old tap)")
    func duplicateSubscribeReplacesPrior() async throws {
        let sessionId = UUID()
        let adapter = PtyStreamStubAdapter(knownSessionId: sessionId)
        let tap = PtyByteTap()
        await adapter.setNextSubscription(tap.subscribe())

        let router = PtyStreamRouterFactory.makeRouter(adapter: adapter)
        let channel = PtyStreamRecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: UUID(),
            negotiatedCodec: .json
        )
        // First subscribe — succeeds.
        try await router.handle(
            envelope: PtyStreamRouterFactory.subscribeEnvelope(sessionId: sessionId),
            replyChannel: channel
        )
        // Second subscribe — replaces the first. Need another live tap
        // since `nextSubscription` self-consumes; otherwise subscribePty
        // returns nil and the second subscribe gets sessionNotFound.
        await adapter.setNextSubscription(tap.subscribe())
        try await router.handle(
            envelope: PtyStreamRouterFactory.subscribeEnvelope(sessionId: sessionId),
            replyChannel: channel
        )

        // Tear down so the test exits cleanly. `cancelPtyStreamSubscription`
        // does NOT call `adapter.unsubscribePty` on duplicate-replace —
        // engine-side `tap.finishAll` releases the old tap subscription
        // when the engine terminates. Verify the explicit unsubscribe
        // still works at the very end.
        try await router.handle(
            envelope: PtyStreamRouterFactory.unsubscribeEnvelope(sessionId: sessionId),
            replyChannel: channel
        )
        let calls = await adapter.unsubscribeCalls
        #expect(calls.count == 1)
    }

    @Test("Unsubscribe with nil sessionId cancels every subscription on the channel")
    func unsubscribeAllOnChannel() async throws {
        let sessionA = UUID()
        let adapter = PtyStreamStubAdapter(knownSessionId: sessionA)
        let tap = PtyByteTap()
        await adapter.setNextSubscription(tap.subscribe())

        let router = PtyStreamRouterFactory.makeRouter(adapter: adapter)
        let channel = PtyStreamRecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: UUID(),
            negotiatedCodec: .json
        )
        try await router.handle(
            envelope: PtyStreamRouterFactory.subscribeEnvelope(sessionId: sessionA),
            replyChannel: channel
        )
        try await router.handle(
            envelope: PtyStreamRouterFactory.unsubscribeEnvelope(sessionId: nil),
            replyChannel: channel
        )
        let calls = await adapter.unsubscribeCalls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == sessionA)
    }

    @Test("connectionClosed cancels every PTY subscription on the channel")
    func connectionClosedTearsDownPtySubscriptions() async throws {
        let sessionId = UUID()
        let adapter = PtyStreamStubAdapter(knownSessionId: sessionId)
        let tap = PtyByteTap()
        await adapter.setNextSubscription(tap.subscribe())

        let router = PtyStreamRouterFactory.makeRouter(adapter: adapter)
        let channel = PtyStreamRecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: UUID(),
            negotiatedCodec: .json
        )
        try await router.handle(
            envelope: PtyStreamRouterFactory.subscribeEnvelope(sessionId: sessionId),
            replyChannel: channel
        )
        await router.connectionClosed(channelId: channel.channelId)

        let calls = await adapter.unsubscribeCalls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == sessionId)
    }

    @Test("Subscribe with malformed payload replies commandRejected")
    func malformedPayloadIsRejected() async throws {
        let adapter = PtyStreamStubAdapter(knownSessionId: UUID())
        let router = PtyStreamRouterFactory.makeRouter(adapter: adapter)
        let channel = PtyStreamRecordingReplyChannel()
        await router.primeAuthenticatedChannel(
            channelId: channel.channelId,
            deviceId: UUID(),
            negotiatedCodec: .json
        )
        // Garbage payload — JSON decode fails and the router replies
        // with commandRejected.
        let bogus = Envelope(
            version: ProtocolVersion.current,
            kind: .ptyStreamSubscribe,
            payload: Data([0xFF, 0xFE, 0xFD])
        )
        await router.handle(envelope: bogus, replyChannel: channel)
        let replies = await channel.snapshot()
        let envelope = try #require(replies.first)
        let error = try envelope.decode(RemoteError.self, codec: JSONRemoteCodec())
        #expect(error.code == .commandRejected)
    }
}
