// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexHeadless",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexHeadless", targets: ["CodexHeadlessApp"]),
        .executable(name: "codex-headless", targets: ["CodexHeadlessCLI"])
    ],
    targets: [
        .target(
            name: "CodexHeadlessCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "CodexHeadlessApp",
            dependencies: ["CodexHeadlessCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "CodexHeadlessCLI",
            dependencies: ["CodexHeadlessCore"]
        )
    ]
)
