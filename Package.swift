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
    dependencies: [
        // 원격 binaryTarget 다운로드가 막힌 환경 대비 로컬 벤더링.
        // 최초 빌드 전 scripts/fetch-sparkle.sh 실행 필요.
        .package(path: "Vendor/Sparkle")
    ],
    targets: [
        .target(name: "WeaveCore"),
        .executableTarget(
            name: "Weave",
            dependencies: [
                "WeaveCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "WeaveCoreTests", dependencies: ["WeaveCore"]),
        .testTarget(name: "WeaveTests", dependencies: ["Weave"])
    ]
)
