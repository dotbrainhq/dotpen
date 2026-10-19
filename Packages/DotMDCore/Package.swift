// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotMDCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DotMDCore", targets: ["DotMDCore"])],
    targets: [
        .target(name: "DotMDCore"),
        .testTarget(name: "DotMDCoreTests", dependencies: ["DotMDCore"]),
    ]
)
