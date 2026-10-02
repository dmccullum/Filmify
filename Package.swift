// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Granular",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "GranularCore", targets: ["GranularCore"]),
        .executable(name: "Granular", targets: ["Granular"])
    ],
    targets: [
        .target(
            name: "GranularCore",
            path: "Sources/GranularCore",
            resources: [
                .copy("FilmStocks")
            ]
        ),
        .executableTarget(
            name: "Granular",
            dependencies: ["GranularCore"],
            path: "Sources/Granular"
        ),
        .testTarget(
            name: "GranularCoreTests",
            dependencies: ["GranularCore"],
            path: "Tests/GranularCoreTests"
        )
    ]
)
