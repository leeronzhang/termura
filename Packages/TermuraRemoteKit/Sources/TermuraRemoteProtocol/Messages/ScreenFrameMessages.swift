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
/// Plain-text only in this MVP — colors, bold, underline, cursor
/// position, and selection are intentionally omitted. The client
/// renders enough to read REPL output (Claude Code, IRB, Python REPL)
/// and basic shell sessions; richer rendering arrives in a follow-up
/// once the wire path is proven.
public struct ScreenFramePayload: Sendable, Codable, Equatable {
    public let sessionId: UUID
    public let frameId: UUID
    public let capturedAt: Date
    public let rows: Int
    public let cols: Int
    public let lines: [String]

    public init(
        sessionId: UUID,
        frameId: UUID = UUID(),
        capturedAt: Date = Date(),
        rows: Int,
        cols: Int,
        lines: [String]
    ) {
        self.sessionId = sessionId
        self.frameId = frameId
        self.capturedAt = capturedAt
        self.rows = rows
        self.cols = cols
        self.lines = lines
    }

    /// Stable digest used by the server-side pulse to skip pushing an
    /// unchanged render. SHA256-isomorphic but plain string hash is
    /// enough — collisions only delay one frame.
    public var renderHash: Int {
        var hasher = Hasher()
        hasher.combine(rows)
        hasher.combine(cols)
        for line in lines {
            hasher.combine(line)
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
