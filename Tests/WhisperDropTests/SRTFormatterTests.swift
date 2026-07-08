import XCTest
@testable import WhisperDrop

final class SRTFormatterTests: XCTestCase {
    func testRendersUTF8CompatibleSRTWithMillisecondTimestamps() {
        let output = SRTFormatter.render([
            SubtitleCue(start: 1.234, end: 62.005, text: " Привет, мир! ")
        ])
        XCTAssertEqual(output, "1\n00:00:01,234 --> 00:01:02,005\nПривет, мир!\n")
    }

    func testClampsNegativeTimestamp() {
        XCTAssertEqual(SRTFormatter.timestamp(-1), "00:00:00,000")
    }

    func testRemovesWhisperControlAndTimestampTokens() {
        let output = SRTFormatter.render([
            SubtitleCue(
                start: 0,
                end: 2.34,
                text: "<|startoftranscript|><|ru|><|transcribe|><|0.00|> Привет!<|2.34|><|endoftext|>"
            )
        ])

        XCTAssertEqual(output, "1\n00:00:00,000 --> 00:00:02,340\nПривет!\n")
    }

    func testRendersWebVTT() {
        let output = SubtitleExporter.render(
            [SubtitleCue(start: 1.25, end: 2.5, text: "Hello")],
            format: .vtt
        )
        XCTAssertEqual(output, "WEBVTT\n\n00:00:01.250 --> 00:00:02.500\nHello\n")
    }

    func testRendersASS() {
        let output = SubtitleExporter.render(
            [SubtitleCue(start: 1.25, end: 62.5, text: "First\nSecond")],
            format: .ass
        )
        XCTAssertTrue(output.contains("Dialogue: 0,0:00:01.25,0:01:02.50,Default,,0,0,0,,First\\NSecond"))
    }

    func testAddsUTF8ByteOrderMark() throws {
        let data = try SubtitleExporter.data("Hello", encoding: .utf8BOM)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
    }
}
