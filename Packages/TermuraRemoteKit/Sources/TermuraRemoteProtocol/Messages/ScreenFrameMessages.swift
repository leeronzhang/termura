import Foundation

/// Client → server: subscribe to live screen frames for one session. The
/// server starts a per-subscription pulse that pushes `.screenFrame`
/// envelopes at `ScreenFramePolicy.pulseInterval`, coalescing identical
/// renders by hash so an idle terminal doesn't burn bandwidth.
public struct ScreenSubscribeRequest: Sendable, Codable, Equatable {
    public let sessionId: UUID

    public init(sessionId: UUID) {
        self.sessionId = sessionId
    }
}

/// Client → server: cancel a prior subscription. Idempotent; cancelling
/// an unknown subscription is silently treated as success so transient
/// duplicate calls (background → foreground churn on iOS) don't surface
/// errors. Sending no `sessionId` cancels every subscription on the
/// channel — used during disconnect / re-pair to make sure the server
/// doesn't keep pushing into a dead reply channel.
public struct ScreenUnsubscribeRequest: Sendable, Codable, Equatable {
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

/// Server → client: one visible-region snapshot of a subscribed session.
/// `lines` is the rendered viewport (no scrollback) split per row, length
/// `rows`. Each entry is `cols` characters wide after Mac-side wrap +
/// truncate; the client should not assume a maximum length and must
/// render with a monospaced font so columns line up.
///
/// `styledLines`, when present, carries the same viewport but with
/// per-cell color and SGR attributes — see `StyledScreenFrame.swift`.
/// Newer clients should prefer `styledLines` and fall back to `lines`
/// when the field is `nil` (older Mac server, or transient extraction
/// failure). Older clients ignore the field entirely thanks to
/// `decodeIfPresent`, so the wire stays backward-compatible.
public struct ScreenFramePayload: Sendable, Codable, Equatable {
    public let sessionId: UUID
    public let frameId: UUID
    public let capturedAt: Date
    public let rows: Int
    public let cols: Int
    public let lines: [String]
    public let styledLines: [StyledLine]?

    public init(
        sessionId: UUID,
        frameId: UUID = UUID(),
        capturedAt: Date = Date(),
        rows: Int,
        cols: Int,
        lines: [String],
        styledLines: [StyledLine]? = nil
    ) {
        self.sessionId = sessionId
        self.frameId = frameId
        self.capturedAt = capturedAt
        self.rows = rows
        self.cols = cols
        self.lines = lines
        self.styledLines = styledLines
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, frameId, capturedAt, rows, cols, lines, styledLines
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        frameId = try container.decode(UUID.self, forKey: .frameId)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        rows = try container.decode(Int.self, forKey: .rows)
        cols = try container.decode(Int.self, forKey: .cols)
        lines = try container.decode([String].self, forKey: .lines)
        styledLines = try container.decodeIfPresent([StyledLine].self, forKey: .styledLines)
    }

    /// Stable digest used by the server-side pulse to skip pushing an
    /// unchanged render. Plain-string hash is enough — collisions only
    /// delay one frame. Includes `styledLines` so a pure-styling change
    /// (e.g. cursor moves under the same character) still triggers a
    /// push.
    public var renderHash: Int {
        var hasher = Hasher()
        hasher.combine(rows)
        hasher.combine(cols)
        for line in lines {
            hasher.combine(line)
        }
        if let styledLines {
            for line in styledLines {
                hasher.combine(line)
            }
        }
        return hasher.finalize()
    }
}

public enum ScreenFramePolicy {
    /// Cadence for the server-side push pulse. 200ms gives a smooth
    /// REPL feel while keeping LAN bandwidth and CloudKit poll churn
    /// reasonable. Coalescing on `renderHash` prevents idle waste.
    public static let pulseInterval: Duration = .milliseconds(200)
}
