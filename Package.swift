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
        .package(path: "../swift-glyph"),
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
