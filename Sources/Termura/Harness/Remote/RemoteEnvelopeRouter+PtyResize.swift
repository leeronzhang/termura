// 1.2 — `.ptyResize` handler. iOS sends a `PtyResizeRequest` after
// reflowing its local SwiftTerm engine, asking the Mac PTY to follow
// so the upstream shell / REPL re-emits output at the new column
// count. Without this round-trip the iOS canvas re-folds bytes that
// Mac auto-wrapped at the wider Mac PTY cols (the legacy folded-
// twice display: `Generat`↵`ive AI [Inoreader].pdf`).
//
// Lifecycle: pure request/response without ack — iOS treats the call
// as fire-and-forget so we never ship a reply envelope (the next
// PTY chunk / checkpoint reflects whatever cols Mac actually moved
// to). The bool returned by `adapter.resizePty(...)` is logged for
// observability but does not cross the wire.
//
// Threat model: same `.authenticated` channel-state requirement as
// the rest of the PTY stream surface; an unauthenticated peer can
// neither subscribe to the byte stream nor change Mac's cell grid.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+PtyResize")

extension RemoteEnvelopeRouter {
    /// Decode `PtyResizeRequest` and forward it to the adapter. The
    /// adapter's bool return signals whether Mac actually moved the
    /// PTY — the A2 guard in `AppDelegate+RemoteBridge.resizeRemotePty`
    /// rejects when `NSApp.isActive == true` so the Mac user's local
    /// terminal view is never resized out from under them. A rejection
    /// is observable here but does NOT surface to iOS (no reply); iOS
    /// keeps its local reflow either way.
    func handlePtyResize(envelope: Envelope, replyChannel: any ReplyChannel) async {
        guard case .authenticated = channels[replyChannel.channelId, default: .unauthenticated] else {
            await replyError(.unauthorized, message: "Pair before resizing the PTY",
                             origin: envelope, via: replyChannel)
            return
        }
        let request: PtyResizeRequest
        do {
            request = try envelope.decode(
                PtyResizeRequest.self,
                codec: codec(for: replyChannel.channelId)
            )
        } catch {
            await replyError(.commandRejected, message: "Bad ptyResize payload",
                             origin: envelope, via: replyChannel)
            return
        }
        let accepted = await adapter.resizePty(
            sessionId: request.sessionId,
            cols: request.cols,
            rows: request.rows
        )
        if !accepted {
            let channelId = replyChannel.channelId
            let sessionId = request.sessionId
            logger.info(
                "PTY resize rejected channel=\(channelId) session=\(sessionId) cols=\(request.cols) rows=\(request.rows)"
            )
        }
    }
}
