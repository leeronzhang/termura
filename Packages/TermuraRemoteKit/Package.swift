// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TermuraRemoteKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TermuraRemoteProtocol",
            targets: ["TermuraRemoteProtocol"]
        ),
        .library(
            name: "TermuraRemoteServer",
            targets: ["TermuraRemoteServer"]
        ),
        .library(
            name: "TermuraRemoteClient",
            targets: ["TermuraRemoteClient"]
        )
    ],
    dependencies: [
        // Pinned to a release tag so contract tests remain stable. Used by
        // `MessagePackRemoteCodec` for the binary wire format negotiated after
        // pairing handshake (handshake itself is always JSON to avoid the
        // first-packet chicken-and-egg problem).
        .package(url: "https://github.com/Flight-School/MessagePack", from: "1.2.4")
    ],
    targets: [
        .target(
            name: "TermuraRemoteProtocol",
            dependencies: [
                .product(name: "MessagePack", package: "MessagePack")
            ],
            path: "Sources/TermuraRemoteProtocol",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "TermuraRemoteServer",
            dependencies: ["TermuraRemoteProtocol"],
            path: "Sources/TermuraRemoteServer",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "TermuraRemoteClient",
            dependencies: ["TermuraRemoteProtocol"],
            path: "Sources/TermuraRemoteClient",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "TermuraRemoteProtocolTests",
            dependencies: ["TermuraRemoteProtocol"],
            path: "Tests/TermuraRemoteProtocolTests"
        ),
        .testTarget(
            name: "TermuraRemoteServerTests",
            dependencies: ["TermuraRemoteServer"],
            path: "Tests/TermuraRemoteServerTests"
        ),
        .testTarget(
            name: "TermuraRemoteClientTests",
            dependencies: ["TermuraRemoteClient"],
            path: "Tests/TermuraRemoteClientTests"
        )
    ]
)
