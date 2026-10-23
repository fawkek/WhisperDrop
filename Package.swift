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
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3")),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperDrop",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
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
