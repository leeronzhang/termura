// Umbrella header for the TermuraAgentXPCInterfaces Clang module.
// Both the LaunchAgent (SwiftPM executable) and the main app (Xcode
// target) `import TermuraAgentXPCInterfaces` to pick up the same XPC
// protocol surface and NSSecureCoding marshaling class.
#import "XPCMailboxItem.h"
#import "AppMailboxProtocol.h"
#import "AgentBridgeProtocol.h"
