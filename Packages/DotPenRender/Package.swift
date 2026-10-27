// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotPenRender",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DotPenRender", targets: ["DotPenRender"])],
    targets: [
        .target(name: "DotPenRender", resources: [.copy("Resources/renderer")]),
        .testTarget(name: "DotPenRenderTests", dependencies: ["DotPenRender"]),
    ]
)
