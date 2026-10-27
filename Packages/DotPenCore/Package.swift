// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DotPenCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DotPenCore", targets: ["DotPenCore"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    ],
    targets: [
        .target(name: "DotPenCore", dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Markdown", package: "swift-markdown"),
        ]),
        .testTarget(name: "DotPenCoreTests", dependencies: ["DotPenCore"]),
    ]
)
