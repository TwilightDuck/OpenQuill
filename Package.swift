// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenWhisper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OpenWhisper", targets: ["OpenWhisper"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: [])
    ],
    targets: [
        .target(name: "FlowCore"),
        .executableTarget(name: "OpenWhisper", dependencies: ["FlowCore", .product(name: "WhisperKit", package: "argmax-oss-swift"), .product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"])
    ]
)
