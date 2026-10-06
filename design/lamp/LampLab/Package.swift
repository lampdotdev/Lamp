// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "LampLab",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "LampLab", path: "Sources/LampLab")]
)
