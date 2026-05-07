#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// PR8 Phase 2 — app → agent forward RPC over the single
// `com.termura.remote-agent` mach service. The agent vends an
// object of this protocol as the `exportedObject` on every accepted
// NSXPCConnection; the main app process retrieves it via
// `outgoingConnection.remoteObjectProxy as AgentBridgeProtocol`.
//
// `pingAgent` is used by the auto-connector at app launch to demand-
// launch the agent via launchd; `stopAgent` is used during graceful
// shutdown.
//
// PR9 — `resetAgentState` is invoked by the resetPairings flow on the
// main app. Unlike ping/stop, the reply is **not** best-effort: the
// main app blocks on the ack so the controller's β-probe + γ-fallback
// path keys off a real "agent has wiped its keychain stores" signal
// rather than a fire-and-forget. The boolean reply value is currently
// unused (any reply means agent ran the reset closure to completion);
// agent-side errors are logged but not surfaced — by design, because
// the main app's β-probe is the authoritative success criterion.
@protocol AgentBridgeProtocol <NSObject>

- (void)pingAgentWithReply:(void (^)(BOOL alive))reply
    NS_SWIFT_NAME(pingAgent(reply:));
- (void)stopAgentWithReply:(void (^)(BOOL accepted))reply
    NS_SWIFT_NAME(stopAgent(reply:));
- (void)resetAgentStateWithReply:(void (^)(BOOL accepted))reply
    NS_SWIFT_NAME(resetAgentState(reply:));

@end

NS_ASSUME_NONNULL_END
