// swift-tools-version: 6.0
import PackageDescription

// PR8 Phase 2 — single-source-of-truth Clang module that carries the
// Objective-C XPC protocol surface (`AgentBridgeProtocol`,
// `AppMailboxProtocol`) and the NSSecureCoding marshaling class
// (`XPCMailboxItem`). Linked by the LaunchAgent SwiftPM executable
// and by the Mac Xcode project so both processes get the same
// symbol table without duplicate compilation.
let package = Package(
    name: "TermuraAgentXPC",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TermuraAgentXPCInterfaces",
            targets: ["TermuraAgentXPCInterfaces"]
        )
    ],
    targets: [
        .target(
            name: "TermuraAgentXPCInterfaces",
            path: "Sources/TermuraAgentXPCInterfaces",
            publicHeadersPath: "include"
        )
    ]
)
