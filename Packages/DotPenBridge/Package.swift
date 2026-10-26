// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotPenBridge",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DotPenBridge", targets: ["DotPenBridge"])],
    targets: [
        .target(name: "DotPenBridge"),
        .testTarget(name: "DotPenBridgeTests", dependencies: ["DotPenBridge"]),
    ]
)
