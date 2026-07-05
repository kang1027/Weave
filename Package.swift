// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Weave",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Weave", targets: ["Weave"]),
        .library(name: "WeaveCore", targets: ["WeaveCore"])
    ],
    targets: [
        .target(name: "WeaveCore"),
        .executableTarget(
            name: "Weave",
            dependencies: ["WeaveCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "WeaveCoreTests", dependencies: ["WeaveCore"])
    ]
)
