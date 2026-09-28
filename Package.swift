// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DarkbloomMonitor",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DarkbloomCompanionProtocol", targets: ["DarkbloomCompanionProtocol"]),
        .library(name: "DarkbloomCompanionTransport", targets: ["DarkbloomCompanionTransport"]),
        .library(name: "DarkbloomCompanionHost", targets: ["DarkbloomCompanionHost"]),
        .library(name: "DarkbloomTelemetry", targets: ["DarkbloomTelemetry"]),
        .executable(name: "DarkbloomMonitor", targets: ["DarkbloomMonitor"]),
        .executable(name: "DarkbloomCompanionFixtureHost", targets: ["DarkbloomCompanionFixtureHost"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.1.0"),
    ],
    targets: [
        .target(name: "DarkbloomCompanionProtocol"),
        .target(
            name: "DarkbloomCompanionTransport",
            dependencies: [
                "DarkbloomCompanionProtocol",
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ]
        ),
        .target(
            name: "DarkbloomCompanionHost",
            dependencies: [
                "DarkbloomCompanionProtocol",
                "DarkbloomCompanionTransport",
                "DarkbloomTelemetry",
            ]
        ),
        .target(
            name: "DarkbloomTelemetry",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "DarkbloomMonitor",
            dependencies: ["DarkbloomTelemetry", .product(name: "Sparkle", package: "Sparkle")],
            exclude: ["Resources/DarkbloomLogo.svg", "Resources/darkbloom-mark.svg", "Resources/darkbloom-menubar.svg"],
            resources: [
                .copy("Resources/dc-mark.svg"),
                .copy("Resources/dc-menubar.svg"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/model-qwen.svg"),
                .copy("Resources/model-openai.svg"),
                .copy("Resources/model-google.svg"),
                .copy("Resources/model-nvidia.svg"),
                .copy("Resources/model-prismml.svg"),
                .copy("Resources/MODEL-ICONS-LICENSE.txt"),
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "DarkbloomCompanionFixtureHost",
            dependencies: [
                "DarkbloomCompanionHost", "DarkbloomCompanionProtocol",
                "DarkbloomCompanionTransport", "DarkbloomTelemetry",
            ]
        ),
        .testTarget(
            name: "DarkbloomTelemetryTests",
            dependencies: ["DarkbloomTelemetry", "DarkbloomMonitor"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DarkbloomCompanionProtocolTests",
            dependencies: ["DarkbloomCompanionProtocol"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DarkbloomCompanionHostTests",
            dependencies: [
                "DarkbloomCompanionHost", "DarkbloomCompanionProtocol",
                "DarkbloomCompanionTransport",
            ]
        ),
    ]
)
