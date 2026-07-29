// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NivelCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NivelCore", targets: ["NivelCore"])],
    targets: [
        .target(name: "NivelCore", resources: [.process("Resources")]),
        .testTarget(name: "NivelCoreTests", dependencies: ["NivelCore"]),
    ]
)
