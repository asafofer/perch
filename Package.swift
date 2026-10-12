// swift-tools-version: 6.2
import PackageDescription

#if os(macOS)
let package = Package(
    name: "Perch",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "PerchCore"),
        .executableTarget(name: "Perch", dependencies: ["PerchCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
    ],
    swiftLanguageModes: [.v5]
)
#else
// Linux: the core and its tests. macOS's SDK has a SQLite3 module; here it comes from the system library.
let package = Package(
    name: "Perch",
    targets: [
        .systemLibrary(name: "SQLite3", path: "Sources/SQLite3", pkgConfig: "sqlite3"),
        .target(name: "PerchCore", dependencies: ["SQLite3"]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
    ],
    swiftLanguageModes: [.v5]
)
#endif
