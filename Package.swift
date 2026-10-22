// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MinimalMC",
    platforms: [
        .iOS(.v15), .macOS(.v12)
    ],
    products: [
        .library(name: "MinimalMC", targets: ["MinimalMC"])
    ],
    targets: [
        .target(
            name: "MinimalMC",
            path: "MinimalMC/Sources/MinimalMC",
            exclude: ["MinimalMCApp.swift"]
        ),
        .testTarget(
            name: "MinimalMCTests",
            dependencies: ["MinimalMC"],
            path: "MinimalMC/Tests/MinimalMCTests"
        )
    ]
)
