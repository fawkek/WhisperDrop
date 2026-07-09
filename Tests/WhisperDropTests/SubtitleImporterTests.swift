import Foundation
import XCTest
@testable import WhisperDrop

final class SubtitleImporterTests: XCTestCase {
    func testImportsSRT() throws {
        let url = try temporaryFile(
            extension: "srt",
            contents: """
            1
            00:00:01,000 --> 00:00:02,500
            Привет, мир.

            2
            00:00:03,000 --> 00:00:04,250
            Second line.
            """
        )

        let cues = try SubtitleImporter.load(url)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0], SubtitleCue(start: 1, end: 2.5, text: "Привет, мир."))
        XCTAssertEqual(cues[1], SubtitleCue(start: 3, end: 4.25, text: "Second line."))
    }

    func testImportsWebVTT() throws {
        let url = try temporaryFile(
            extension: "vtt",
            contents: """
            WEBVTT

            00:00:01.250 --> 00:00:02.500
            Hello.
            """
        )

        let cues = try SubtitleImporter.load(url)

        XCTAssertEqual(cues, [SubtitleCue(start: 1.25, end: 2.5, text: "Hello.")])
    }

    private func temporaryFile(extension pathExtension: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(pathExtension)
        try contents.data(using: .utf8)?.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
