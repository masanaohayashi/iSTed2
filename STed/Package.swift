// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "STed",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "STedCore", targets: ["STedCore"]),
        .library(name: "STedPlayback", targets: ["STedPlayback"]),
        .executable(name: "STedApp", targets: ["STedApp"]),
        .executable(name: "STedPlay", targets: ["STedPlay"])
    ],
    targets: [
        .target(name: "STedCore"),
        .target(
            name: "STedPlayback",
            dependencies: ["STedCore"]
        ),
        .executableTarget(
            name: "STedApp",
            dependencies: ["STedCore", "STedPlayback"]
        ),
        .executableTarget(
            name: "STedPlay",
            dependencies: ["STedCore", "STedPlayback"]
        ),
        .testTarget(
            name: "STedCoreTests",
            dependencies: ["STedCore"]
        ),
        .testTarget(
            name: "STedPlaybackTests",
            dependencies: ["STedPlayback"]
        )
    ]
)
