#import <Foundation/Foundation.h>
#import "XPCMailboxItem.h"

NS_ASSUME_NONNULL_BEGIN

// PR8 Phase 2 — agent → app reverse RPC over the single
// `com.termura.remote-agent` mach service. The main app process
// vends an object of this protocol as the `exportedObject` on the
// outgoing NSXPCConnection it owns; the agent process retrieves it
// via `inboundConnection.remoteObjectProxy as AppMailboxProtocol`.
//
// Reply contract (PR8 Phase 2 §7 / reply payload patch):
//   * success    — terminal-business success vs. retryable failure.
//                  See §7.2 error classification table for the
//                  per-reasonCode mapping. dispatcher only inspects
//                  this Bool when deciding delete/advance/quarantine.
//   * reasonCode — short ASCII tag, never nil. When the outcome has
//                  no specific reason, the bridge passes @"ok"
//                  (success path) or @"unspecified" (failure path).
//                  reasonCode does not influence dispatcher behaviour
//                  beyond the success Bool — it is used for
//                  diagnostics, log lines, and test assertions only.
@protocol AppMailboxProtocol <NSObject>

- (void)deliverMailboxItem:(XPCMailboxItem *)item
                     reply:(void (^)(BOOL success, NSString *reasonCode))reply
    NS_SWIFT_NAME(deliverMailboxItem(_:reply:));

@end

NS_ASSUME_NONNULL_END
