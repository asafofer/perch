// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "PerchCore"),
        .executableTarget(name: "Perch", dependencies: ["PerchCore"]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
    ],
    swiftLanguageModes: [.v5]
)
