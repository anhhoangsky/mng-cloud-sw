// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MNGKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MNGKit", targets: ["MNGKit"])
    ],
    targets: [
        .target(name: "MNGKit"),
        .testTarget(name: "MNGKitTests", dependencies: ["MNGKit"])
    ]
)
