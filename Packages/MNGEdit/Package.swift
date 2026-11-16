// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MNGEdit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MNGEdit", targets: ["MNGEdit"])
    ],
    targets: [
        .target(
            name: "MNGEdit",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "MNGEditTests",
            dependencies: ["MNGEdit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
