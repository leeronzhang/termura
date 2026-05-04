import Foundation
import TermuraRemoteProtocol

/// Builds a `PtyStreamCheckpoint` keyframe from a live `TerminalEngine`'s
/// rendered viewport. The harness router calls this on cold-start (right
/// after a `.ptyStreamSubscribe` arrives) and on its 30 s / 256-chunk
/// cadence so iOS clients can re-sync without replaying the full byte
/// history.
///
/// Re-uses the same `engine.readVisibleStyledScreen()` path that
/// `captureRemoteScreen` already drives for the legacy `.screenFrame`
/// pulse — the underlying `ghostty_surface_snapshot_viewport` call is
/// non-flag-consuming, so checkpointing does not stall the host's Metal
/// renderer (the v1 issue documented in `AppDelegate+RemoteBridge.swift`).
///
/// Cursor row/col are placeholders for now (set to 0,0). Ghostty's
/// embedding API does not yet expose cursor position alongside the
/// snapshot; the engine emits cursor moves as part of the byte stream
/// itself, so the SwiftTerm engine on iOS will keep its own cursor in
/// sync after applying the checkpoint and resuming the byte stream. A
/// future ghostty-side patch (or styled-extractor extension) can fill
/// these in for sub-millisecond first-frame fidelity.
@MainActor
enum PtyCheckpointProvider {
    /// Build a checkpoint from `engine`'s current visible viewport.
    /// Returns `nil` when the engine has no live surface (pre-attach
    /// lifecycle, post-terminate, or transient extraction failure).
    /// `seq` is set by the caller (the router's pump) so the checkpoint
    /// slots into the same monotonic sequence the chunks share.
    static func makeCheckpoint(
        engine: any TerminalEngine,
        sessionId: UUID,
        seq: UInt64,
        producedAt: Date = Date()
    ) -> PtyStreamCheckpoint? {
        if let styled = engine.readVisibleStyledScreen(), !styled.lines.isEmpty {
            return PtyStreamCheckpoint(
                sessionId: sessionId,
                seq: seq,
                rows: styled.rows,
                cols: styled.cols,
                lines: styled.lines,
                styledLines: styled.styledLines,
                cursorRow: 0,
                cursorCol: 0,
                producedAt: producedAt
            )
        }
        guard let plain = engine.readVisibleScreen() else { return nil }
        return PtyStreamCheckpoint(
            sessionId: sessionId,
            seq: seq,
            rows: plain.rows,
            cols: plain.cols,
            lines: plain.lines,
            styledLines: nil,
            cursorRow: 0,
            cursorCol: 0,
            producedAt: producedAt
        )
    }
}
