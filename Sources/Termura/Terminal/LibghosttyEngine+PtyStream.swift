import Foundation
import TermuraRemoteProtocol

extension LibghosttyEngine {
    /// Returns a fresh subscription handle whose `stream` yields raw PTY
    /// bytes as the IO callback receives them. Caller must
    /// `await unsubscribeBytes(id:)` via the returned handle (or rely
    /// on `terminate()`'s `finishAll()`) when done.
    ///
    /// `async` on the protocol method but synchronous internally — the
    /// underlying `PtyByteTap` uses an unfair lock for ordering, not
    /// an actor, so the call returns immediately.
    func subscribeBytes() async -> PtyByteTap.Subscription? {
        ptyByteTap.subscribe()
    }

    /// Cancel a single byte-stream subscription. Idempotent.
    func unsubscribeBytes(id: UUID) async {
        ptyByteTap.unsubscribe(id: id)
    }

    /// Build a `PtyStreamCheckpoint` from the engine's current visible
    /// viewport. Drives the harness router's cold-start keyframe and
    /// the periodic 30 s / 256-chunk resync keyframe.
    func currentCheckpoint(sessionId: UUID, seq: UInt64) -> PtyStreamCheckpoint? {
        PtyCheckpointProvider.makeCheckpoint(engine: self, sessionId: sessionId, seq: seq)
    }
}
