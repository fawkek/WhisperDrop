import CryptoKit
import XCTest
@testable import WhisperDrop

final class ModelDownloaderTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "WhisperDropTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "weights"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let content = Data((0..<5_000).map { UInt8($0 % 251) })

    private var manifest: [ModelFile] {
        let hash = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        return [ModelFile(path: "weights/weight.bin", size: Int64(content.count), sha256: hash)]
    }

    private var destination: URL { folder.appending(path: "weights/weight.bin") }
    private var partial: URL { destination.appendingPathExtension("partial") }

    func testRecoversCompletePartialWithAppendedTail() throws {
        try (content + Data(repeating: 7, count: 300)).write(to: partial)
        try ModelDownloader.repairValidOversizedFiles(in: folder, manifest: manifest)
        XCTAssertEqual(try Data(contentsOf: destination), content)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testTrimsOversizedFinishedFile() throws {
        try (content + Data(repeating: 1, count: 10)).write(to: destination)
        try ModelDownloader.repairValidOversizedFiles(in: folder, manifest: manifest)
        XCTAssertEqual(try Data(contentsOf: destination), content)
    }

    func testLeavesCorruptedPartialForRedownload() throws {
        var corrupted = content
        corrupted[10] ^= 0xFF
        try (corrupted + Data(repeating: 7, count: 300)).write(to: partial)
        try ModelDownloader.repairValidOversizedFiles(in: folder, manifest: manifest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path))
    }

    func testLeavesIncompletePartialAlone() throws {
        try content.prefix(1_000).write(to: partial)
        try ModelDownloader.repairValidOversizedFiles(in: folder, manifest: manifest)
        XCTAssertEqual(ModelDownloader.fileSize(partial), 1_000)
    }

    func testFileSizeSeesGrowthOfSameURL() throws {
        try Data(count: 10).write(to: partial)
        XCTAssertEqual(ModelDownloader.fileSize(partial), 10)
        let handle = try FileHandle(forWritingTo: partial)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(count: 90))
        try handle.close()
        XCTAssertEqual(ModelDownloader.fileSize(partial), 100)
    }
}
