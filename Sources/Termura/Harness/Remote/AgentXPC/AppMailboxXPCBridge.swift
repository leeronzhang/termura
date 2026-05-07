// PR8 Phase 2 — NSObject XPC adapter that vends `AppMailboxProtocol`
// on the main app side. Sits on the outgoing NSXPCConnection's
// `exportedObject` so the agent can call back into the app via
// `inboundConnection.remoteObjectProxy as AppMailboxProtocol`. The
// bridge stays thin: it converts `XPCMailboxItem` → Swift wire
// struct, hops onto `MainActor`, awaits the actor ingress, and
// translates the `AppMailboxReply` strong type into the bare
// `(BOOL, NSString *)` reply block parameters (reply payload patch
// — method A, no NSSecureCoding wrapper).

import Foundation
import OSLog
@preconcurrency import TermuraAgentXPCInterfaces
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "AppMailboxXPCBridge")

// `AppMailboxXPCBridge` is `@unchecked Sendable` because NSXPC vends
// the same instance to multiple threads via `exportedObject`. Thread
// safety: the only stored state is an immutable `@Sendable` closure
// (`ingressProvider`); the actual ingress is an `actor` that
// serialises its own access.
@objc
final class AppMailboxXPCBridge: NSObject, AppMailboxProtocol, @unchecked Sendable {
    private let ingressProvider: @Sendable () async -> AgentInjectedCloudKitIngress?

    init(ingressProvider: @escaping @Sendable () async -> AgentInjectedCloudKitIngress?) {
        self.ingressProvider = ingressProvider
        super.init()
    }

    func deliverMailboxItem(_ item: XPCMailboxItem, reply: @escaping (Bool, String) -> Void) {
        guard let kind = AgentMailboxItem.PayloadKind(rawValue: item.payloadKind) else {
            logger.warning("unknown payloadKind \(item.payloadKind, privacy: .public); rejecting as retry")
            reply(false, "kind_mismatch")
            return
        }
        let swiftItem = AgentMailboxItem(
            recordName: item.recordName,
            createdAt: item.createdAt,
            sourceDeviceId: item.sourceDeviceID,
            payloadKind: kind,
            payloadData: item.payloadData,
            schemaVersion: item.schemaVersion
        )
        let provider = ingressProvider
        let box = ReplyBox(reply: reply)
        Task {
            guard let ingress = await provider() else {
                box.invoke(success: false, reasonCode: "shutdown")
                return
            }
            let outcome = await ingress.ingest(item: swiftItem)
            box.invoke(success: outcome.success, reasonCode: outcome.reasonCode)
        }
    }
}

// NSXPC reply blocks are invoked exactly once on whatever queue the
// XPC runtime picks; in practice they are thread-safe to call. Swift
// 6 strict concurrency can't see through the ObjC bridge, so we
// wrap the block in an `@unchecked Sendable` envelope. The box itself
// is immutable; once-only-invocation is enforced by callers, not by
// the box.
private struct ReplyBox: @unchecked Sendable {
    let reply: (Bool, String) -> Void

    func invoke(success: Bool, reasonCode: String) {
        reply(success, reasonCode)
    }
}
