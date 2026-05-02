import Foundation

/// Client → server: subscribe to a session's raw PTY byte stream so the
/// client can run its own vt engine locally and reflow content to its own
/// viewport (iPhone / iPad columns differ from the Mac PTY columns). The
/// server immediately ships one `.ptyStreamCheckpoint` keyframe (cold-start
/// basis) and then streams `.ptyStreamChunk` envelopes coalesced by
/// `PtyStreamPolicy`.
///
/// `resumeFromSeq` lets a client that briefly disconnected (scenePhase
/// background → foreground, transient network blip) ask the server to
/// replay bytes from a known sequence number instead of full re-init. When
/// the server's resume ring no longer holds that range it falls back to a
/// fresh checkpoint.
public struct PtyStreamSubscribeRequest: Sendable, Codable, Equatable {
    public let sessionId: UUID
    public let resumeFromSeq: UInt64?

    public init(sessionId: UUID, resumeFromSeq: UInt64? = nil) {
        self.sessionId = sessionId
        self.resumeFromSeq = resumeFromSeq
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, resumeFromSeq
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        resumeFromSeq = try container.decodeIfPresent(UInt64.self, forKey: .resumeFromSeq)
    }
}

/// Client → server: cancel a prior `.ptyStreamSubscribe`. Idempotent;
/// cancelling an unknown subscription is silently treated as success so
/// transient duplicate calls (background → foreground churn on iOS) don't
/// surface errors. Sending no `sessionId` cancels every PTY subscription
/// on the channel — used during disconnect / re-pair to make sure the
/// server doesn't keep streaming into a dead reply channel.
public struct PtyStreamUnsubscribeRequest: Sendable, Codable, Equatable {
    public let sessionId: UUID?

    public init(sessionId: UUID? = nil) {
        self.sessionId = sessionId
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(UUID.self, forKey: .sessionId)
    }
}

/// Server → client: a coalesced batch of raw PTY bytes from a subscribed
/// session, ready to feed into the client's local vt engine.
///
/// `seq` is monotonic per `(channel, session)` and starts at `1` after
/// each fresh subscribe. The very first envelope shipped on a subscription
/// is always a `.ptyStreamCheckpoint` carrying `seq` = 0; the first
/// `.ptyStreamChunk` is `seq` = 1. Clients use `seq` to detect gaps and
/// trigger `.ptyStreamSubscribe { resumeFromSeq: lastApplied }`.
///
/// `payload` is opaque bytes — the server does not parse VT/ANSI here.
/// Sanitization (deny OSC 52 clipboard write, DCS, etc.) happens at the
/// client's `TerminalDelegate` shim per security policy.
public struct PtyStreamChunk: Sendable, Codable, Equatable {
    public let sessionId: UUID
    public let seq: UInt64
    public let payload: Data
    public let producedAt: Date

    public init(sessionId: UUID, seq: UInt64, payload: Data, producedAt: Date = Date()) {
        self.sessionId = sessionId
        self.seq = seq
        self.payload = payload
        self.producedAt = producedAt
    }
}

/// Server → client: a keyframe carrying the full visible viewport so the
/// client's vt engine can cold-restore (or re-sync after a `seq` gap)
/// without replaying the entire byte history.
///
/// Built on the server side from `ghostty_surface_snapshot_viewport` —
/// the same data shape the existing `ScreenFramePayload` carries — plus
/// cursor position. After applying a checkpoint the client resets its vt
/// engine, feeds the lines back as if re-initializing, and resumes
/// applying `.ptyStreamChunk` envelopes from `seq + 1`.
///
/// `styledLines` is optional for the same reason `ScreenFramePayload`
/// allows it — older surfaces / transient extraction failures fall back
/// to plain text. New clients should prefer `styledLines` when present.
public struct PtyStreamCheckpoint: Sendable, Codable, Equatable {
    public let sessionId: UUID
    public let seq: UInt64
    public let rows: Int
    public let cols: Int
    public let lines: [String]
    public let styledLines: [StyledLine]?
    public let cursorRow: Int
    public let cursorCol: Int
    public let producedAt: Date

    public init(
        sessionId: UUID,
        seq: UInt64,
        rows: Int,
        cols: Int,
        lines: [String],
        styledLines: [StyledLine]? = nil,
        cursorRow: Int,
        cursorCol: Int,
        producedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.seq = seq
        self.rows = rows
        self.cols = cols
        self.lines = lines
        self.styledLines = styledLines
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
        self.producedAt = producedAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, seq, rows, cols, lines, styledLines, cursorRow, cursorCol, producedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        seq = try container.decode(UInt64.self, forKey: .seq)
        rows = try container.decode(Int.self, forKey: .rows)
        cols = try container.decode(Int.self, forKey: .cols)
        lines = try container.decode([String].self, forKey: .lines)
        styledLines = try container.decodeIfPresent([StyledLine].self, forKey: .styledLines)
        cursorRow = try container.decode(Int.self, forKey: .cursorRow)
        cursorCol = try container.decode(Int.self, forKey: .cursorCol)
        producedAt = try container.decode(Date.self, forKey: .producedAt)
    }
}

/// Server-side coalescing parameters for the byte-stream pump. The values
/// trade three things off:
///
/// - `coalesceTimeMax` (8 ms) keeps end-to-end input latency well under
///   the 16 ms terminal-input SLO. Bytes spend at most one frame's worth
///   of time waiting in the coalescer.
/// - `coalesceBytesMax` (32 KB) caps individual envelope size so a single
///   large write (`cat 1MB.bin`) doesn't produce a bloated WebSocket frame.
/// - `idleFlushCeiling` (200 ms) ensures the very last byte of an idle
///   stream still ships even if it never crossed the 32 KB threshold.
///
/// `checkpointEvery` and `checkpointEveryChunks` define the cadence at
/// which the server inserts a `.ptyStreamCheckpoint` so resume / cold-
/// restore stay cheap (no full byte replay).
public enum PtyStreamPolicy {
    public static let coalesceBytesMax: Int = 32 * 1024
    public static let coalesceTimeMax: Duration = .milliseconds(8)
    public static let idleFlushCeiling: Duration = .milliseconds(200)
    public static let checkpointEvery: Duration = .seconds(30)
    public static let checkpointEveryChunks: Int = 256
}
