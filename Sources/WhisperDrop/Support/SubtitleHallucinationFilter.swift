import Foundation

/// Removes text Whisper is known to invent over silence, music or noise.
///
/// Two levels:
/// - `clean(_:)` works on finished cues (also used after proofreading and on imported
///   subtitles) and only removes phrases that are practically never real speech.
/// - `clean(segments:)` runs right after transcription, while Whisper's own quality
///   metrics are still available, and can also drop silent, looping or repeated segments.
enum SubtitleHallucinationFilter {
    // Phrases removed whenever they make up a whole cue or segment.
    private static let exactPhrases: Set<String> = [
        "девушки отдыхают",
        "girls are relaxing",
    ]

    // Subtitle credits from Whisper's training data; matched as a prefix.
    private static let creditPrefixes = [
        "субтитры сделал",
        "субтитры делал",
        "субтитры создавал",
        "субтитры подготовил",
        "субтитры подогнал",
        "редактор субтитров",
        "корректор а егорова",
        "subtitles by",
        "subtitles made by",
        "transcription by",
        "transcribed by",
    ]

    // Credits matched anywhere in the text.
    private static let creditFragments = [
        "дима торжок",
        "dima torzhok",
        "синецкая",
        "amara org",
    ]

    // Outro phrases that are usually invented, but can be real speech; removed only
    // when Whisper's metrics also look doubtful.
    private static let suspiciousPhrases: Set<String> = [
        "продолжение следует",
        "спасибо за просмотр",
        "спасибо за внимание",
        "подписывайтесь на канал",
        "подписывайтесь на наш канал",
        "ставьте лайки",
        "до новых встреч",
        "thank you for watching",
        "thanks for watching",
        "thank you",
        "please subscribe",
        "subscribe to my channel",
        "see you next time",
    ]

    /// Cue-level cleanup.
    static func clean(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        cues.filter { !isKnownHallucination($0.text) }
    }

    static func isKnownHallucination(_ text: String) -> Bool {
        let value = normalized(text)
        guard !value.isEmpty else { return true }
        return exactPhrases.contains(value)
            || creditPrefixes.contains(where: value.hasPrefix)
            || creditFragments.contains(where: value.contains)
    }

    /// Segment-level cleanup that runs before cues are built.
    static func clean(segments: [TranscribedSegment]) -> [TranscribedSegment] {
        var kept: [TranscribedSegment] = []
        var repeatRun = 0
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let value = normalized(segment.text)
            guard !value.isEmpty, !isKnownHallucination(segment.text) else { continue }

            // Nobody says this much this fast: ~40 characters per second is far beyond
            // even rapid speech, and a few words in a fraction of a second is invented.
            let duration = max(0.001, segment.end - segment.start)
            if Double(value.count) / duration > 40 || (duration < 0.25 && value.count > 6) { continue }
            // Whisper's own silence test: likely no speech and low confidence.
            if segment.noSpeechProb > 0.6 && segment.avgLogprob < -1.0 { continue }
            // Very repetitive output that survived temperature fallback is a decoding loop.
            if segment.compressionRatio > 2.8 { continue }
            // Typical outro phrases are kept only when Whisper is confident it heard speech.
            if suspiciousPhrases.contains(value),
               segment.noSpeechProb > 0.3 || segment.avgLogprob < -0.7 { continue }

            // The same sentence repeated again and again is a loop; keep the first two.
            if let previous = kept.last, normalized(previous.text) == value, value.count >= 10 {
                repeatRun += 1
                if repeatRun >= 2 { continue }
            } else {
                repeatRun = 0
            }

            kept.append(collapsingRepeatedWords(segment))
        }
        return kept
    }

    /// Shortens in-segment loops such as "и вот и вот и вот и вот…" to two repetitions.
    static func collapsingRepeatedWords(_ segment: TranscribedSegment) -> TranscribedSegment {
        let words = segment.timedWords
        guard words.count >= 8 else { return segment }
        let keys = words.map { normalized($0.text) }
        var keep = Array(repeating: true, count: words.count)
        var changed = false

        for size in 1...6 {
            var index = 0
            while index + size * 2 <= keys.count {
                let pattern = Array(keys[index..<index + size])
                guard !pattern.allSatisfy(\.isEmpty) else { index += 1; continue }
                var repeats = 1
                var cursor = index + size
                while cursor + size <= keys.count, Array(keys[cursor..<cursor + size]) == pattern {
                    repeats += 1
                    cursor += size
                }
                // Natural speech repeats a word or two ("да, да, да, да"); six single
                // words or four longer phrases in a row is a decoding loop.
                if repeats >= (size == 1 ? 6 : 4) {
                    for drop in (index + size * 2)..<cursor { keep[drop] = false }
                    changed = true
                    index = cursor
                } else {
                    index += 1
                }
            }
        }
        guard changed else { return segment }

        var result = segment
        result.words = zip(words, keep).filter(\.1).map(\.0)
        result.text = result.words.map(\.text).joined(separator: " ")
        if let last = result.words.last { result.end = min(segment.end, last.end) }
        return result
    }

    private static func normalized(_ text: String) -> String {
        let folded = WhisperTextSanitizer.clean(text)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
        let words = folded.unicodeScalars.split { scalar in
            !CharacterSet.alphanumerics.contains(scalar)
        }
        return words.map(String.init).joined(separator: " ")
    }
}
