// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotMDCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DotMDCore", targets: ["DotMDCore"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "DotMDCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "DotMDCoreTests", dependencies: ["DotMDCore"]),
    ]
)
