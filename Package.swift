// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Catch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Catch", targets: ["Catch"])
    ],
    targets: [
        .executableTarget(
            name: "Catch",
            path: "Sources/Catch"
        )
    ]
)
