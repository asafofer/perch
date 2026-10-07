// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "PerchCore"),
        .target(name: "PerchUI", dependencies: ["PerchCore"]),
        .executableTarget(name: "Perch", dependencies: ["PerchCore", "PerchUI"]),
        .executableTarget(name: "PerchSnapshots", dependencies: ["PerchCore", "PerchUI"]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
    ],
    swiftLanguageModes: [.v5]
)
