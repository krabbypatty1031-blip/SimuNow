// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimuKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SimuCore", targets: ["SimuCore"]),
        .library(name: "SimuSimulation", targets: ["SimuSimulation"]),
        .library(name: "SimuWorkspace", targets: ["SimuWorkspace"]),
        .library(name: "SimuVisualization", targets: ["SimuVisualization"]),
        .library(name: "SimuReporting", targets: ["SimuReporting"]),
        .library(name: "SimuDesignSystem", targets: ["SimuDesignSystem"])
    ],
    targets: [
        .target(name: "SimuCore"),
        .target(name: "SimuSimulation", dependencies: ["SimuCore"]),
        .target(name: "SimuDesignSystem"),
        .target(name: "SimuVisualization", dependencies: ["SimuCore", "SimuDesignSystem"]),
        .target(name: "SimuReporting", dependencies: ["SimuCore"]),
        .target(name: "SimuWorkspace", dependencies: [
            "SimuCore", "SimuSimulation", "SimuVisualization", "SimuReporting", "SimuDesignSystem"
        ]),
        .testTarget(name: "SimuCoreTests", dependencies: ["SimuCore", "SimuSimulation", "SimuWorkspace", "SimuReporting"]),
        .testTarget(name: "SimuVisualizationTests", dependencies: ["SimuVisualization", "SimuCore"])
    ]
)
