// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GearChanger",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "gearchanger", targets: ["GearChangerCLI"]),
        .library(name: "GearChangerCore", targets: ["GearChangerCore"]),
        .library(name: "GearChangerAdapters", targets: ["GearChangerAdapters"])
    ],
    targets: [
        .target(
            name: "GearChangerCore",
            path: "Sources/GearChangerCore"
        ),
        .target(
            name: "GearChangerAdapters",
            dependencies: ["GearChangerCore"],
            path: "Sources/GearChangerAdapters"
        ),
        .executableTarget(
            name: "GearChangerCLI",
            dependencies: ["GearChangerCore", "GearChangerAdapters"],
            path: "Sources/GearChangerCLI"
        ),
        .testTarget(
            name: "GearChangerCoreTests",
            dependencies: ["GearChangerCore"],
            path: "Tests/GearChangerCoreTests"
        )
    ]
)
