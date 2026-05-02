import Foundation
import os

/// One-to-many fan-out of raw PTY bytes from the ghostty surface IO callback
/// to N independent subscribers (typically: the harness router's pty-stream
/// pump). Sits next to the existing `LibghosttyEngine.outputStream` consumer
/// (which feeds OSC 133 / `AgentStateDetector`) — the IO callback yields
/// once into each path so the Mac local Ghostty render is never bypassed
/// or starved.
///
/// Threading & ordering
/// --------------------
///
/// `feedNonisolated(_:)` is the entrypoint called from ghostty's IO thread.
/// **Byte order must be preserved across fan-out**: VT/ANSI escape
/// sequences depend on byte order, and a single re-ordering causes vim,
/// htop, and tmux to render incorrectly downstream. We therefore can NOT
/// route through an actor (multiple `Task { await … }` enqueues do not
/// preserve enqueue order). Instead, the IO thread acquires an unfair
/// lock briefly to fan out via `AsyncStream.Continuation.yield`, which is
/// thread-safe and synchronous. The yield call itself does not block —
/// it pushes into the stream's internal bounded buffer (per
/// `bufferingNewest`) and returns immediately, so the lock hold time is
/// O(N subscribers) of pointer copies, well below any IO-thread budget.
///
/// Lifecycle
/// ---------
///
/// - **OWNER**: `LibghosttyEngine` constructs and holds one `PtyByteTap` per
///   live engine.
/// - **TEARDOWN**: `engine.terminate()` calls `tap.finishAll()` to finish
///   every subscriber's stream cleanly.
/// - **TEST**: `PtyByteTapTests`.
///
/// Open-core
/// ---------
///
/// `PtyByteTap.Subscription` is a public type defined in the public
/// `Termura` module. The paid harness consumes `Subscription.stream`
/// through the `RemoteSessionsAdapter.subscribePty(sessionId:)` protocol
/// method, which keeps private impl symbols out of public-repo files.
public final class PtyByteTap: Sendable {
    /// Handle returned to a caller of `subscribe()`. The caller awaits
    /// `stream` for incoming PTY bytes and must call
    /// `unsubscribe(id:)` (or rely on `finishAll()` at engine teardown)
    /// when done.
    public struct Subscription: Sendable {
        public let id: UUID
        public let stream: AsyncStream<Data>
    }

    /// All mutable state is encapsulated under a single unfair lock so
    /// the IO-thread `feedNonisolated` and any caller-thread
    /// subscribe / unsubscribe / finishAll are serialized without an
    /// async hop. `OSAllocatedUnfairLock<State>` itself is `Sendable`,
    /// so the enclosing class is `Sendable` without per-field unsafe
    /// markers — every mutation goes through `state.withLock`.
    private struct State {
        var subscribers: [UUID: AsyncStream<Data>.Continuation] = [:]
        var closed: Bool = false
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    public init() {}

    /// Register a new subscriber and return its handle. After
    /// `finishAll()` has run, returns a stream that finishes
    /// immediately so a late caller doesn't get stuck awaiting bytes
    /// from a dead engine.
    public func subscribe() -> Subscription {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        state.withLock { state in
            if state.closed {
                continuation.finish()
            } else {
                state.subscribers[id] = continuation
            }
        }
        return Subscription(id: id, stream: stream)
    }

    /// Cancel a single subscription. Idempotent — unknown ids are
    /// silently ignored so callers don't have to track closed state.
    public func unsubscribe(id: UUID) {
        let cont = state.withLock { state in
            state.subscribers.removeValue(forKey: id)
        }
        cont?.finish()
    }

    /// Finish every active subscription. Called from
    /// `LibghosttyEngine.terminate` so subscribers see a clean stream
    /// end and exit their `for await` loops without lingering on a
    /// dead engine.
    public func finishAll() {
        let pending = state.withLock { state -> [AsyncStream<Data>.Continuation] in
            state.closed = true
            let continuations = Array(state.subscribers.values)
            state.subscribers.removeAll()
            return continuations
        }
        for continuation in pending {
            continuation.finish()
        }
    }

    /// IO-thread entrypoint. Fan out synchronously under the lock: the
    /// individual `continuation.yield(data)` calls are thread-safe and
    /// non-blocking (they push into the stream's bounded buffer and
    /// return immediately), so total hold time is O(N subscribers) of
    /// pointer copies — well under any IO-thread budget. Critical:
    /// preserves byte order across all subscribers, which VT/ANSI
    /// sequences require.
    public func feedNonisolated(_ data: Data) {
        state.withLock { state in
            guard !state.closed else { return }
            for (_, continuation) in state.subscribers {
                continuation.yield(data)
            }
        }
    }

    /// Number of currently-active subscribers. Cheap — used by tests
    /// and the diagnostics layer (W5) to surface "is anyone listening"
    /// stats. Returns 0 after `finishAll()`.
    public var activeSubscriberCount: Int {
        state.withLock(\.subscribers.count)
    }
}
