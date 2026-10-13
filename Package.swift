// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceWalk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SpaceWalk", targets: ["SpaceWalk"])],
    targets: [
        .executableTarget(name: "SpaceWalk"),
        .testTarget(name: "SpaceWalkTests", dependencies: ["SpaceWalk"])
    ]
)
