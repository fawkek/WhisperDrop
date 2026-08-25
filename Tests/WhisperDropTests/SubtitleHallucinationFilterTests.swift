import XCTest
@testable import WhisperDrop

final class SubtitleHallucinationFilterTests: XCTestCase {
    func testRemovesKnownRussianHallucinationsRegardlessOfCaseAndPunctuation() {
        let cues = [
            SubtitleCue(start: 0, end: 2, text: "Субтитры сделал Дима Торжок."),
            SubtitleCue(start: 3, end: 5, text: "ДЕВУШКИ ОТДЫХАЮТ!"),
            SubtitleCue(start: 6, end: 8, text: "Настоящая реплика."),
            SubtitleCue(start: 9, end: 11, text: "Девушки отдыхают…"),
        ]

        XCTAssertEqual(
            SubtitleHallucinationFilter.clean(cues),
            [SubtitleCue(start: 6, end: 8, text: "Настоящая реплика.")]
        )
    }

    func testRemovesCreditPhraseWithTrailingNoise() {
        XCTAssertTrue(SubtitleHallucinationFilter.isKnownHallucination(
            "Субтитры делал Дима Торжок — www.example.com"
        ))
    }

    func testKeepsSimilarButMeaningfulSpeech() {
        XCTAssertFalse(SubtitleHallucinationFilter.isKnownHallucination("Девушки отдыхают у моря завтра."))
        XCTAssertFalse(SubtitleHallucinationFilter.isKnownHallucination("Дима сделал хорошие субтитры."))
    }
}
