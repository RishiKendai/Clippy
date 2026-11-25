// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clippy", targets: ["Clippy"])
    ],
    targets: [
        // Database, models and pasteboard codec. No UI; fully unit-tested.
        .target(
            name: "ClippyCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // The menu bar app: AppKit glue, services and SwiftUI views.
        .executableTarget(
            name: "Clippy",
            dependencies: ["ClippyCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "ClippyTests",
            dependencies: ["ClippyCore"]
        ),
    ]
)
