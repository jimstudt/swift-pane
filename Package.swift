// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "swift-pane",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "SwiftPane", targets: ["SwiftPane"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jimstudt/swift-glyph.git", from: "0.1.2"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "SwiftPane",
            dependencies: [
                .product(name: "SwiftGlyph", package: "swift-glyph"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
            ]
        ),
        .testTarget(
            name: "SwiftPaneTests",
            dependencies: ["SwiftPane"],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
            ]
        ),
    ]
)
