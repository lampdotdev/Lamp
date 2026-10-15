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
            dependencies: [.product(name: "Sparkle", package: "Sparkle"), "LampSidebarKit"],
            path: "Sources/Lamp",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // What Lamp and the chat inside an app's window say to each other.
        .target(name: "LampSidebarKit", path: "Sources/LampSidebarKit"),
        // That chat: an extension Lamp puts in every Mac app it builds. It starts as Apple's own extensions do,
        // through the system's extension entry point, which sets it up before its `main` runs.
        .executableTarget(
            name: "LampSidebar",
            dependencies: ["LampSidebarKit"],
            path: "Sources/LampSidebar",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"])]
        ),
        .testTarget(name: "LampTests", dependencies: ["Lamp"], path: "Tests/Regression"),
    ]
)
