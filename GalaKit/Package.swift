// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GalaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GalaKit", targets: ["GalaKit"]),
    ],
    targets: [
        .target(name: "GalaKit", resources: [.copy("Resources/Profiles")]),
        .executableTarget(name: "gala-cli", dependencies: ["GalaKit"]),
        .testTarget(name: "GalaKitTests", dependencies: ["GalaKit"]),
    ]
)
