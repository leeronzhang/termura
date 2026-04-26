// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "termura-notes",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TermuraNotesKit", targets: ["TermuraNotesKit"]),
        .executable(name: "termura-notes", targets: ["TermuraNotesCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.5.0"),
    ],
    targets: [
        .target(
            name: "TermuraNotesKit",
            path: "Sources/TermuraNotesKit"
        ),
        .executableTarget(
            name: "TermuraNotesCLI",
            dependencies: [
                "TermuraNotesKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/TermuraNotesCLI"
        ),
        .testTarget(
            name: "TermuraNotesKitTests",
            dependencies: ["TermuraNotesKit"],
            path: "Tests/TermuraNotesKitTests"
        ),
    ]
)
