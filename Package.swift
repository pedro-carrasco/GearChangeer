// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GearChanger",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "gearchanger", targets: ["GearChangerCLI"]),
        .executable(name: "GearChangerMenuBar", targets: ["GearChangerMenuBar"]),
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
        .executableTarget(
            name: "GearChangerMenuBar",
            dependencies: ["GearChangerCore", "GearChangerAdapters"],
            path: "Sources/GearChangerMenuBar",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GearChangerCoreTests",
            dependencies: ["GearChangerCore"],
            path: "Tests/GearChangerCoreTests"
        )
    ]
)
