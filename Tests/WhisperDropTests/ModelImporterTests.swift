import CryptoKit
import XCTest
@testable import WhisperDrop

final class ModelImporterTests: XCTestCase {
    private var root: URL!
    private let weights = Data((0..<4_000).map { UInt8($0 % 199) })
    private let config = Data("{}".utf8)

    private var manifest: [ModelFile] {
        let hash = SHA256.hash(data: weights).map { String(format: "%02x", $0) }.joined()
        return [
            ModelFile(path: "Encoder.mlmodelc/weights/weight.bin", size: Int64(weights.count), sha256: hash),
            ModelFile(path: "config.json", size: Int64(config.count)),
        ]
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "WhisperDropImport-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(at folder: URL, weights data: Data? = nil) throws {
        let weightsURL = folder.appending(path: "Encoder.mlmodelc/weights/weight.bin")
        try FileManager.default.createDirectory(at: weightsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data ?? weights).write(to: weightsURL)
        try config.write(to: folder.appending(path: "config.json"))
    }

    func testImportsModelFromNestedFolderAndKeepsSource() throws {
        let source = root.appending(path: "Backups/models/whisper-large")
        try makeModel(at: source)
        let destination = root.appending(path: "Installed")

        try ModelImporter.importModel(from: root, to: destination, manifest: manifest) { _ in }

        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "Encoder.mlmodelc/weights/weight.bin")), weights)
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "config.json")), config)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appending(path: "config.json").path))
    }

    func testRejectsDifferentWeights() throws {
        var other = weights
        other[0] ^= 0xFF
        try makeModel(at: root.appending(path: "model"), weights: other)

        XCTAssertThrowsError(
            try ModelImporter.importModel(from: root, to: root.appending(path: "Installed"), manifest: manifest) { _ in }
        ) { error in
            XCTAssertTrue(error is ModelImporter.ModelMismatchError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "Installed").path))
    }

    func testReportsMissingModel() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(
            try ModelImporter.importModel(from: root, to: root.appending(path: "Installed"), manifest: manifest) { _ in }
        ) { error in
            XCTAssertTrue(error is ModelImporter.ModelNotFoundError)
        }
    }
}
