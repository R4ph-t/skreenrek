// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "skreenrek",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "skreenrek", targets: ["skreenrek"]),
    ],
    targets: [
        .target(name: "SkreenrekCore"),
        .target(name: "SkreenrekSystem", dependencies: ["SkreenrekCore"]),
        .target(name: "SkreenrekTesting", dependencies: ["SkreenrekCore"]),
        .executableTarget(name: "skreenrek", dependencies: ["SkreenrekCore", "SkreenrekSystem"]),
        .testTarget(name: "SkreenrekCoreTests", dependencies: ["SkreenrekCore", "SkreenrekTesting"]),
        .testTarget(name: "SkreenrekSystemTests", dependencies: ["SkreenrekCore", "SkreenrekSystem"]),
    ],
    swiftLanguageModes: [.v6]
)
