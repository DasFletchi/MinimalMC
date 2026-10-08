// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MinimalMC",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "MinimalMC", targets: ["MinimalMC"])
    ],
    targets: [
        .target(
            name: "MinimalMC",
            path: "MinimalMC/Sources/MinimalMC",
            exclude: ["MinimalMCApp.swift"] // Exclude app entry point for testing library code
        ),
        .testTarget(
            name: "MinimalMCTests",
            dependencies: ["MinimalMC"],
            path: "MinimalMC/Tests/MinimalMCTests"
        )
    ]
)
