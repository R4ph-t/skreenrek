// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "skreenrek",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "skreenrek", targets: ["skreenrek"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
    ],
    targets: [
        .target(name: "SkreenrekCore"),
        .target(name: "SkreenrekSystem", dependencies: ["SkreenrekCore"]),
        .target(name: "SkreenrekTesting", dependencies: ["SkreenrekCore"]),
        .target(name: "SkreenrekControl", dependencies: ["SkreenrekCore"]),
        .target(
            name: "SkreenrekCLI",
            dependencies: [
                "SkreenrekCore", "SkreenrekControl",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .executableTarget(
            name: "skreenrek", dependencies: ["SkreenrekCore", "SkreenrekSystem", "SkreenrekControl", "SkreenrekCLI"]),
        .testTarget(name: "SkreenrekCoreTests", dependencies: ["SkreenrekCore", "SkreenrekTesting"]),
        .testTarget(name: "SkreenrekSystemTests", dependencies: ["SkreenrekCore", "SkreenrekSystem"]),
        .testTarget(
            name: "SkreenrekControlTests", dependencies: ["SkreenrekControl", "SkreenrekCore", "SkreenrekTesting"]),
        .testTarget(
            name: "SkreenrekCLITests",
            dependencies: ["SkreenrekCLI", "SkreenrekControl", "SkreenrekCore", "SkreenrekTesting"]),
    ],
    swiftLanguageModes: [.v6]
)
