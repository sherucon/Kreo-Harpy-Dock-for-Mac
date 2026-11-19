// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HarpyDock",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HarpyDock", targets: ["HarpyDock"]),
        .executable(name: "harpyctl", targets: ["harpyctl"]),
    ],
    targets: [
        .target(
            name: "HarpyDockCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(name: "HarpyDock", dependencies: ["HarpyDockCore"]),
        .executableTarget(name: "harpyctl", dependencies: ["HarpyDockCore"]),
        .testTarget(name: "HarpyDockCoreTests", dependencies: ["HarpyDockCore"]),
    ]
)
