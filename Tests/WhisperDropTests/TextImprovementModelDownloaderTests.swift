import CryptoKit
import XCTest
@testable import WhisperDrop

final class TextImprovementModelDownloaderTests: XCTestCase {
    private var folder: URL!
    private let content = Data((0..<5_000).map { UInt8($0 % 251) })

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ProofreadingModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "weights"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var model: ProofreadingModel {
        ProofreadingModel(
            id: "test", displayName: "Test", repository: "test/model",
            files: [
                ModelFile(path: "config.json", size: 2),
                ModelFile(path: "weights/model.bin", size: Int64(content.count),
                          sha256: SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()),
            ],
            russianNote: "", englishNote: ""
        )
    }

    private var destination: URL { folder.appending(path: "weights/model.bin") }
    private var partial: URL { destination.appendingPathExtension("partial") }

    func testInstallsCompletePartialsWithHashVerification() async throws {
        try Data("{}".utf8).write(to: folder.appending(path: "config.json.partial"))
        try content.write(to: partial)

        try await TextImprovementModelDownloader.downloadFiles(model, in: folder) { _, _ in }

        XCTAssertEqual(try Data(contentsOf: destination), content)
        XCTAssertTrue(TextImprovementModelLocator.isInstalled(model, in: folder))
        XCTAssertEqual(TextImprovementModelLocator.downloadedBytes(model, in: folder), model.size)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testRecoversVerifiedOversizedPartial() async throws {
        try Data("{}".utf8).write(to: folder.appending(path: "config.json"))
        try (content + Data(repeating: 7, count: 300)).write(to: partial)

        try await TextImprovementModelDownloader.downloadFiles(model, in: folder) { _, _ in }

        XCTAssertEqual(try Data(contentsOf: destination), content)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testCancellationPreservesPartialAndInstalledFiles() async throws {
        let directory = folder!
        let fixture = model
        try Data("{}".utf8).write(to: directory.appending(path: "config.json"))
        try content.prefix(1_000).write(to: partial)

        let task = Task {
            try await TextImprovementModelDownloader.downloadFiles(fixture, in: directory) { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(ModelDownloader.fileSize(partial), 1_000)
            XCTAssertEqual(ModelDownloader.fileSize(directory.appending(path: "config.json")), 2)
            XCTAssertFalse(TextImprovementModelLocator.isInstalled(fixture, in: directory))
            XCTAssertEqual(TextImprovementModelLocator.downloadedBytes(fixture, in: directory), 1_002)
        }
    }

    func testInstallationRequiresEveryManifestFileAtExactSize() throws {
        try Data("{}".utf8).write(to: folder.appending(path: "config.json"))
        XCTAssertFalse(TextImprovementModelLocator.isInstalled(model, in: folder))
        try (content + Data([0])).write(to: destination)
        XCTAssertFalse(TextImprovementModelLocator.isInstalled(model, in: folder))
        try content.write(to: destination)
        XCTAssertTrue(TextImprovementModelLocator.isInstalled(model, in: folder))
    }
}
