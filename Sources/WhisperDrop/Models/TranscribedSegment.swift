import Foundation

/// A recognized word with its own timing. Kept independent from WhisperKit so the
/// subtitle pipeline can be unit-tested without a model.
struct TranscribedWord: Codable, Equatable, Sendable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var probability: Double = 1
    /// True when timing was spread from the segment rather than aligned by Whisper.
    var isEstimated = false
}

/// A Whisper segment plus the quality metrics Whisper reports for it.
struct TranscribedSegment: Codable, Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var words: [TranscribedWord]
    var avgLogprob: Double = 0
    var compressionRatio: Double = 1
    var noSpeechProb: Double = 0

    /// Words with usable timing. When Whisper returns no word timings, the segment
    /// text is spread across the segment proportionally to word length.
    var timedWords: [TranscribedWord] {
        let real = words
            .map { word -> TranscribedWord in
                var copy = word
                copy.text = WhisperTextSanitizer.clean(word.text)
                return copy
            }
            .filter { !$0.text.isEmpty }
        if !real.isEmpty { return real }

        let tokens = WhisperTextSanitizer.clean(text)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty, end > start else { return [] }
        let totalLength = Double(tokens.reduce(0) { $0 + $1.count })
        var cursor = start
        return tokens.map { token in
            let share = (end - start) * Double(token.count) / max(1, totalLength)
            defer { cursor += share }
            return TranscribedWord(text: token, start: cursor, end: cursor + share, isEstimated: true)
        }
    }
}
