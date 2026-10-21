// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotMDBridge",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DotMDBridge", targets: ["DotMDBridge"])],
    targets: [
        .target(name: "DotMDBridge"),
        .testTarget(name: "DotMDBridgeTests", dependencies: ["DotMDBridge"]),
    ]
)
