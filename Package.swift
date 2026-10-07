// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lamp",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Updates for release builds (MIT). build.sh copies Sparkle.framework into Forge.app/Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Lamp",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Lamp",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "LampTests", dependencies: ["Lamp"], path: "Tests/Regression"),
    ]
)
