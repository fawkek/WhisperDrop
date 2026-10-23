import XCTest
@testable import WhisperDrop

/// Builds a segment whose words are spoken back to back at `wordDuration` each,
/// with optional extra pauses before given word indexes.
private func segment(
    _ text: String,
    start: TimeInterval = 0,
    wordDuration: TimeInterval = 0.3,
    pauses: [Int: TimeInterval] = [:],
    noSpeechProb: Double = 0,
    avgLogprob: Double = -0.2,
    compressionRatio: Double = 1.5
) -> TranscribedSegment {
    var cursor = start
    var words: [TranscribedWord] = []
    for (index, word) in text.split(separator: " ").enumerated() {
        cursor += pauses[index] ?? 0
        words.append(TranscribedWord(text: " " + word, start: cursor, end: cursor + wordDuration))
        cursor += wordDuration
    }
    return TranscribedSegment(
        start: start,
        end: cursor,
        text: text,
        words: words,
        avgLogprob: avgLogprob,
        compressionRatio: compressionRatio,
        noSpeechProb: noSpeechProb
    )
}

final class LineBreakerTests: XCTestCase {
    func testShortTextStaysOnOneLine() {
        XCTAssertEqual(LineBreaker.lines(for: ["Привет,", "мир!"]), ["Привет, мир!"])
    }

    func testLongTextSplitsIntoBalancedLinesWithinLimit() throws {
        let words = "Мы приехали в город поздно вечером и сразу пошли искать гостиницу".split(separator: " ").map(String.init)
        let lines = try XCTUnwrap(LineBreaker.lines(for: words))
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.count <= 42 })
        XCTAssertLessThan(abs(lines[0].count - lines[1].count), 20)
    }

    func testDoesNotLeavePrepositionAtLineEnd() throws {
        let words = "Сегодня утром я долго шёл пешком через весь старый парк к реке".split(separator: " ").map(String.init)
        let lines = try XCTUnwrap(LineBreaker.lines(for: words))
        for line in lines.dropLast() {
            let last = String(line.split(separator: " ").last ?? "")
            XCTAssertFalse(WeakWords.contains(last), "line ends with weak word: \(line)")
        }
    }

    func testPrefersBreakAfterComma() throws {
        let words = "Когда мы вернулись домой, на кухне уже горел свет и пахло хлебом".split(separator: " ").map(String.init)
        let lines = try XCTUnwrap(LineBreaker.lines(for: words))
        XCTAssertEqual(lines.first, "Когда мы вернулись домой,")
    }

    func testRejectsTextThatCannotFitTwoLines() {
        let words = Array(repeating: "слово", count: 30)
        XCTAssertNil(LineBreaker.lines(for: words))
    }

    func testRewrapsLongProofreadLine() {
        let text = "Мы приехали в город поздно вечером и сразу пошли искать гостиницу"
        let result = LineBreaker.rewrapIfNeeded(text)
        XCTAssertTrue(result.contains("\n"))
        XCTAssertEqual(LineBreaker.rewrapIfNeeded("Короткая строка."), "Короткая строка.")
    }
}

final class CueSegmenterTests: XCTestCase {
    func testLongSegmentIsCutIntoReadableCues() {
        let text = """
        Сегодня мы поговорим о том, как устроены субтитры. Хорошие субтитры легко читать, \
        они не закрывают половину экрана и появляются вместе с речью. Плохие субтитры \
        приходится ловить глазами, потому что строки слишком длинные и текст висит слишком долго.
        """
        let cues = CueSegmenter.cues(from: [segment(text)])
        XCTAssertGreaterThan(cues.count, 3)
        for cue in cues {
            let lines = cue.text.components(separatedBy: "\n")
            XCTAssertLessThanOrEqual(lines.count, 2, cue.text)
            XCTAssertTrue(lines.allSatisfy { $0.count <= 42 }, cue.text)
            XCTAssertLessThanOrEqual(cue.end - cue.start, 7.0001, cue.text)
        }
        // No word is lost or duplicated.
        let rebuilt = cues.map { $0.text.replacingOccurrences(of: "\n", with: " ") }.joined(separator: " ")
        XCTAssertEqual(rebuilt, text)
    }

    func testSentenceEndStartsNewCue() {
        let cues = CueSegmenter.cues(from: [segment("Это была очень длинная и тяжёлая неделя. Теперь отдыхаем.")])
        XCTAssertEqual(cues.map(\.text), ["Это была очень длинная и тяжёлая неделя.", "Теперь отдыхаем."])
    }

    func testShortSentencesCanShareCue() {
        let cues = CueSegmenter.cues(from: [segment("Да. Нет. Может быть.")])
        XCTAssertEqual(cues.count, 1)
    }

    func testPauseStartsNewCue() {
        let cues = CueSegmenter.cues(from: [segment("Подожди меня здесь хорошо", pauses: [3: 1.5])])
        XCTAssertEqual(cues.map(\.text), ["Подожди меня здесь", "хорошо"])
    }

    func testCueTimingFollowsWords() {
        let cues = CueSegmenter.cues(from: [segment("Первая фраза здесь.", start: 10)])
        XCTAssertEqual(cues.first?.start ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(cues.first?.end ?? 0, 10.9, accuracy: 0.001)
    }

    func testStretchedFirstWordAfterSilenceIsShortened() {
        var seg = segment("Ну вот и всё.", start: 5)
        seg.words[0].start = 1 // alignment pulled "Ну" four seconds into the silence
        seg.start = 1
        let cues = CueSegmenter.cues(from: [seg])
        XCTAssertGreaterThan(cues[0].start, 4.0)
    }

    func testFallsBackToSegmentTextWithoutWordTimings() {
        let seg = TranscribedSegment(start: 0, end: 4, text: " Привет, как дела?", words: [])
        let cues = CueSegmenter.cues(from: [seg])
        XCTAssertEqual(cues.map(\.text), ["Привет, как дела?"])
        XCTAssertEqual(cues[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 4, accuracy: 0.001)
    }

    func testStrayPunctuationAttachesToPreviousWord() {
        var seg = segment("Привет мир")
        seg.words.append(TranscribedWord(text: "!", start: 0.6, end: 0.6))
        XCTAssertEqual(CueSegmenter.cues(from: [seg]).map(\.text), ["Привет мир!"])
    }
}

final class CueTimingNormalizerTests: XCTestCase {
    func testRemovesOverlapsAndKeepsGap() {
        let cues = CueTimingNormalizer.normalize([
            SubtitleCue(start: 0, end: 3, text: "Первая реплика"),
            SubtitleCue(start: 2.5, end: 5, text: "Вторая реплика"),
        ])
        XCTAssertLessThanOrEqual(cues[0].end + 0.0799, cues[1].start)
    }

    func testExtendsShortCueToReadingTime() {
        let text = "Довольно длинная реплика, которую нужно успеть прочитать"
        let cues = CueTimingNormalizer.normalize([SubtitleCue(start: 10, end: 11, text: text)])
        XCTAssertGreaterThanOrEqual(cues[0].end - cues[0].start, Double(text.count) / 17 - 0.001)
    }

    func testAddsTailWhenThereIsRoom() {
        let cues = CueTimingNormalizer.normalize([
            SubtitleCue(start: 0, end: 2, text: "Да."),
            SubtitleCue(start: 10, end: 12, text: "Нет."),
        ])
        XCTAssertEqual(cues[0].end, 2.2, accuracy: 0.001)
    }

    func testClosesSmallGaps() {
        let cues = CueTimingNormalizer.normalize([
            SubtitleCue(start: 0, end: 2, text: "Первая"),
            SubtitleCue(start: 2.4, end: 4, text: "Вторая"),
        ])
        XCTAssertEqual(cues[0].end, 2.32, accuracy: 0.001)
    }

    func testNeverExceedsMaxDuration() {
        let cues = CueTimingNormalizer.normalize([SubtitleCue(start: 0, end: 20, text: "Долго")])
        XCTAssertLessThanOrEqual(cues[0].end - cues[0].start, 7.0001)
    }

    func testCuesStayInOrderAndNonOverlapping() {
        let input = (0..<20).map { SubtitleCue(start: Double($0) * 0.4, end: Double($0) * 0.4 + 0.3, text: "Слово \($0)") }
        let cues = CueTimingNormalizer.normalize(input)
        for (a, b) in zip(cues, cues.dropFirst()) {
            XCTAssertLessThan(a.start, a.end)
            XCTAssertLessThanOrEqual(a.end, b.start)
        }
    }
}

final class SegmentHallucinationTests: XCTestCase {
    func testDropsSilentLowConfidenceSegment() {
        let cleaned = SubtitleHallucinationFilter.clean(segments: [
            segment("Настоящая речь здесь."),
            segment("Какой-то шум.", start: 5, noSpeechProb: 0.8, avgLogprob: -1.3),
        ])
        XCTAssertEqual(cleaned.map(\.text), ["Настоящая речь здесь."])
    }

    func testDropsCreditsAndLoops() {
        let cleaned = SubtitleHallucinationFilter.clean(segments: [
            segment("Редактор субтитров А.Синецкая Корректор А.Егорова"),
            segment("бла бла бла", start: 3, compressionRatio: 3.5),
            segment("Нормальная фраза.", start: 6),
        ])
        XCTAssertEqual(cleaned.map(\.text), ["Нормальная фраза."])
    }

    func testOutroPhraseNeedsDoubtfulMetrics() {
        let confident = segment("Спасибо за просмотр!", noSpeechProb: 0.05, avgLogprob: -0.2)
        let doubtful = segment("Спасибо за просмотр!", start: 10, noSpeechProb: 0.5, avgLogprob: -0.9)
        let cleaned = SubtitleHallucinationFilter.clean(segments: [confident, doubtful])
        XCTAssertEqual(cleaned.count, 1)
        XCTAssertEqual(cleaned.first?.start, 0)
    }

    func testRepeatedSentenceLoopKeepsTwo() {
        let line = "Мы будем рады видеть вас снова."
        let cleaned = SubtitleHallucinationFilter.clean(segments: (0..<5).map { segment(line, start: Double($0) * 3) })
        XCTAssertEqual(cleaned.count, 2)
    }

    func testCollapsesWordLoopInsideSegment() {
        let seg = segment("и вот и вот и вот и вот и вот и вот конец")
        let collapsed = SubtitleHallucinationFilter.collapsingRepeatedWords(seg)
        XCTAssertEqual(collapsed.words.map { $0.text.trimmingCharacters(in: .whitespaces) }, ["и", "вот", "и", "вот", "конец"])
    }

    func testKeepsNaturalRepetition() {
        let seg = segment("да да да да хорошо мы идём домой")
        XCTAssertEqual(SubtitleHallucinationFilter.collapsingRepeatedWords(seg), seg)
    }

    func testFullPipelineProducesCleanCues() {
        let cues = TranscriptionService.cues(from: [
            segment("Субтитры сделал Дима Торжок"),
            segment("Привет. Сегодня покажу, как сделать хорошие субтитры для своего видео за пять минут.", start: 4),
        ])
        XCTAssertFalse(cues.contains { $0.text.contains("Торжок") })
        XCTAssertTrue(cues.allSatisfy { $0.text.components(separatedBy: "\n").allSatisfy { $0.count <= 42 } })
    }
}
