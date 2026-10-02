// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Forge", path: "Sources/Forge")]
)
