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
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "SkreenrekCore"),
        .target(name: "SkreenrekSystem", dependencies: ["SkreenrekCore"]),
        .target(name: "SkreenrekTesting", dependencies: ["SkreenrekCore"]),
        .target(name: "SkreenrekControl", dependencies: ["SkreenrekCore"]),
        .target(name: "SkreenrekMCP", dependencies: ["SkreenrekCore", "SkreenrekControl"]),
        .target(
            name: "SkreenrekCLI",
            dependencies: [
                "SkreenrekCore", "SkreenrekControl", "SkreenrekMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .target(
            name: "SkreenrekUI",
            dependencies: [
                "SkreenrekControl", "SkreenrekCore", .product(name: "Sparkle", package: "Sparkle"),
            ]),
        .executableTarget(
            name: "skreenrek",
            dependencies: ["SkreenrekCore", "SkreenrekSystem", "SkreenrekControl", "SkreenrekCLI", "SkreenrekUI"],
            // Skreenrek.app embeds Sparkle.framework in Contents/Frameworks (scripts/bundle-app.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "SkreenrekCoreTests", dependencies: ["SkreenrekCore", "SkreenrekTesting"]),
        .testTarget(name: "SkreenrekSystemTests", dependencies: ["SkreenrekCore", "SkreenrekSystem"]),
        .testTarget(
            name: "SkreenrekControlTests", dependencies: ["SkreenrekControl", "SkreenrekCore", "SkreenrekTesting"]),
        .testTarget(
            name: "SkreenrekCLITests",
            dependencies: ["SkreenrekCLI", "SkreenrekControl", "SkreenrekCore", "SkreenrekTesting"]),
        .testTarget(
            name: "SkreenrekUITests",
            dependencies: ["SkreenrekUI", "SkreenrekControl", "SkreenrekCore", "SkreenrekTesting"]),
        .testTarget(
            name: "SkreenrekMCPTests",
            dependencies: ["SkreenrekMCP", "SkreenrekControl", "SkreenrekCore", "SkreenrekTesting"]),
    ],
    swiftLanguageModes: [.v6]
)
