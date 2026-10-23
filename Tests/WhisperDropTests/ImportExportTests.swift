import XCTest
@testable import WhisperDrop

final class ImportExportTests: XCTestCase {
    private let russianSRT = "1\r\n00:00:01,000 --> 00:00:02,500\r\nПривет, как дела? Съёмки начинаются завтра.\r\n"

    func testDecodesWindows1251Russian() throws {
        let data = try XCTUnwrap(russianSRT.data(using: .windowsCP1251))
        XCTAssertEqual(SubtitleImporter.decode(data), russianSRT)
    }

    func testDecodesWindows1252Western() throws {
        let text = "1\n00:00:01,000 --> 00:00:02,000\nCafé crème, déjà vu.\n"
        let data = try XCTUnwrap(text.data(using: .windowsCP1252))
        XCTAssertEqual(SubtitleImporter.decode(data), text)
    }

    func testDecodesUTF16WithAndWithoutBOM() throws {
        let le = try XCTUnwrap(russianSRT.data(using: .utf16LittleEndian))
        XCTAssertEqual(SubtitleImporter.decode(Data([0xFF, 0xFE]) + le), russianSRT)
        XCTAssertEqual(SubtitleImporter.decode(le), russianSRT)
    }

    func testDecodesUTF8WithBOM() throws {
        XCTAssertEqual(SubtitleImporter.decode(Data([0xEF, 0xBB, 0xBF]) + Data(russianSRT.utf8)), russianSRT)
    }

    func testRejectsPlainTextWithoutTimecodes() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString).txt")
        try "Купить молоко\nПозвонить маме".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try SubtitleImporter.load(url)) { error in
            XCTAssertEqual(error as? SubtitleImportError, .plainTextWithoutTimecodes)
        }
    }

    func testStripsASSOverrideTags() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "s-\(UUID().uuidString).ass")
        try "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\i1}Привет{\\i0},\\Nмир\\hвокруг\n"
            .write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try SubtitleImporter.load(url).first?.text, "Привет,\nмир вокруг")
    }

    func testCleansVTTVoiceTagsAndEntities() {
        XCTAssertEqual(SubtitleImporter.cleanVTTMarkup("<v Анна>Да &amp; нет</v>"), "Да & нет")
    }

    func testEscapesVTTMarkupCharacters() {
        let output = SubtitleExporter.render([SubtitleCue(start: 0, end: 1, text: "a < b & c --> d")], format: .vtt)
        XCTAssertTrue(output.contains("a &lt; b &amp; c --&gt; d"))
    }

    func testASSBracesDoNotBecomeOverrides() {
        let output = SubtitleExporter.render([SubtitleCue(start: 0, end: 1, text: "{шёпот} тише")], format: .ass)
        XCTAssertTrue(output.hasSuffix(",(шёпот) тише\n"))
    }

    func testBlankLinesInsideCueDoNotBreakSRT() {
        let output = SRTFormatter.render([SubtitleCue(start: 0, end: 1, text: "Первая\n\nвторая")])
        XCTAssertEqual(output, "1\n00:00:00,000 --> 00:00:01,000\nПервая\nвторая\n")
    }
}
