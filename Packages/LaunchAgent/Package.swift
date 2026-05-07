// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TermuraRemoteAgent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "termura-remote-agent",
            targets: ["termura-remote-agent"]
        )
    ],
    dependencies: [
        // PR8 Phase 2 — XPC interface module shared with the main app.
        .package(path: "../AgentXPCInterfaces"),
        // CloudKit envelope types, PairKey store, codec abstractions.
        .package(path: "../TermuraRemoteKit")
    ],
    targets: [
        .executableTarget(
            name: "termura-remote-agent",
            dependencies: [
                .product(name: "TermuraAgentXPCInterfaces", package: "AgentXPCInterfaces"),
                .product(name: "TermuraRemoteProtocol", package: "TermuraRemoteKit")
            ],
            path: "Sources/termura-remote-agent",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "TermuraRemoteAgentTests",
            dependencies: [
                "termura-remote-agent",
                .product(name: "TermuraAgentXPCInterfaces", package: "AgentXPCInterfaces"),
                .product(name: "TermuraRemoteProtocol", package: "TermuraRemoteKit")
            ],
            path: "Tests/TermuraRemoteAgentTests"
        )
    ]
)
