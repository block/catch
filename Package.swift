// swift-tools-version: 6.2

import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances")
]

let package = Package(
    name: "Catch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Catch", targets: ["Catch"])
    ],
    targets: [
        .target(
            name: "CatchKit",
            path: "Sources/Catch",
            swiftSettings: concurrencySettings
        ),
        .executableTarget(
            name: "Catch",
            dependencies: ["CatchKit"],
            path: "Sources/CatchApp",
            swiftSettings: concurrencySettings
        )
    ],
    swiftLanguageModes: [.v6]
)
