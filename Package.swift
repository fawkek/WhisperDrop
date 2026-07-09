// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperDrop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhisperDrop", targets: ["WhisperDrop"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "2.31.3")),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMinor(from: "0.31.3"))
    ],
    targets: [
        .executableTarget(
            name: "WhisperDrop",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLX", package: "mlx-swift")
            ],
            path: "Sources/WhisperDrop"
        ),
        .testTarget(
            name: "WhisperDropTests",
            dependencies: ["WhisperDrop"]
        )
    ],
    swiftLanguageModes: [.v5]
)
