// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MNGCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MNGCore", targets: ["MNGCore"])
    ],
    targets: [
        .target(name: "MNGCore"),
        .testTarget(
            name: "MNGCoreTests",
            dependencies: ["MNGCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
