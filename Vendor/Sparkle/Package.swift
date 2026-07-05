// swift-tools-version: 5.9
// Sparkle 로컬 벤더 래퍼 — xcframework는 scripts/fetch-sparkle.sh로 받는다.
import PackageDescription

let package = Package(
    name: "Sparkle",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "Sparkle", targets: ["Sparkle"])
    ],
    targets: [
        .binaryTarget(name: "Sparkle", path: "Sparkle.xcframework")
    ]
)
