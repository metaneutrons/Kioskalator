// swift-tools-version: 6.2
import PackageDescription

// This manifest is authoritative for the dependency graph and for
// Package.resolved. The Xcode project generated from project.yml consumes this
// package and is seeded with this lockfile in CI; see CONTRIBUTING.md.
let package = Package(
    name: "KioskCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KioskCore", targets: ["KioskCore"])
    ],
    targets: [
        .target(
            name: "KioskCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "KioskCoreTests",
            dependencies: ["KioskCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
    ]
)
