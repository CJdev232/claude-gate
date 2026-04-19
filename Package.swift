// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "claude-gate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "claude-gate", targets: ["ClaudeGate"]),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeGate",
            dependencies: ["ClaudeGateLib"],
            path: "Sources/ClaudeGate"
        ),
        .target(
            name: "ClaudeGateLib",
            path: "Sources/ClaudeGateLib",
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
