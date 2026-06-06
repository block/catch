// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexSessions",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexSessions", targets: ["CodexSessions"])
    ],
    targets: [
        .executableTarget(
            name: "CodexSessions",
            path: "Sources/CodexSessions"
        )
    ]
)
