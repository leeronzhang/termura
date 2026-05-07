// PR8 Phase 2 (reply payload patch) — Swift-internal strong type for
// the ingress's terminal-vs-retryable outcome. Lives only inside the
// main-app process: bridges into `(BOOL, NSString *)` at the XPC seam
// (see `AppMailboxXPCBridge`) and dispatches into the §7.2 error
// classification table on the agent side. Not Codable, not exposed
// to ObjC; the wire shape is the bare reply block parameters.

import Foundation

struct AppMailboxReply: Sendable, Equatable {
    let success: Bool
    let reasonCode: String

    static let ok = AppMailboxReply(success: true, reasonCode: "ok")

    static func terminal(_ reasonCode: String) -> AppMailboxReply {
        AppMailboxReply(success: true, reasonCode: reasonCode)
    }

    static func retry(_ reasonCode: String) -> AppMailboxReply {
        AppMailboxReply(success: false, reasonCode: reasonCode)
    }
}
