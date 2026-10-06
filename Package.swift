// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Updates for release builds (MIT). build.sh copies Sparkle.framework into Forge.app/Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Forge",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Forge",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
