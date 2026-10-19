// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotMDRender",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DotMDRender", targets: ["DotMDRender"])],
    targets: [
        .target(name: "DotMDRender", resources: [.copy("Resources/renderer")]),
        .testTarget(name: "DotMDRenderTests", dependencies: ["DotMDRender"]),
    ]
)
