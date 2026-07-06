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
}

