// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperDrop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhisperDrop", targets: ["WhisperDrop"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "WhisperDrop",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
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
