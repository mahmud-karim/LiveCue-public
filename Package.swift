// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LiveCueCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LiveCueCore", targets: ["LiveCueCore"])],
    targets: [
        .target(name: "LiveCueCore"),
        .testTarget(name: "LiveCueCoreTests", dependencies: ["LiveCueCore"])
    ]
)

