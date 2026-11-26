// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RoamJournal",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TrailCore", targets: ["TrailCore"])],
    targets: [
        .target(name: "TrailCore", path: "RoamJournal/Core"),
        .target(name: "NativeCatalog", path: "Examples/NativeCatalog", publicHeadersPath: "include"),
        .target(name: "LegacyRouteLab", dependencies: ["NativeCatalog"], path: "Examples/LegacyRouteLab"),
        .testTarget(name: "TrailCoreTests", dependencies: ["TrailCore"]),
        .testTarget(name: "LegacyRouteLabTests", dependencies: ["LegacyRouteLab"])
    ], cxxLanguageStandard: .cxx17
)
