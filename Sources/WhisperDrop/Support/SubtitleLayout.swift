import Foundation

/// Readability rules for generated subtitles. Defaults follow common broadcast and
/// streaming guidelines (42 characters per line, two lines, 1–7 seconds per cue).
struct SubtitleLayout: Equatable, Sendable {
    var maxCharsPerLine = 42
    var maxLines = 2
    var minDuration: TimeInterval = 1.0
    var maxDuration: TimeInterval = 7.0
    /// Target reading speed in characters per second (spaces and punctuation included).
    var maxCharsPerSecond = 17.0
    /// A silence at least this long always starts a new cue.
    var pauseBreak: TimeInterval = 0.7
    /// Once a cue holds this many characters, a sentence end closes it.
    var sentenceBreakMinChars = 24
    /// Minimum gap kept between consecutive cues (about two video frames).
    var minGap: TimeInterval = 0.08
    /// Extra time a cue stays on screen after the last spoken word.
    var tail: TimeInterval = 0.2
    /// Gaps shorter than this are closed so cues don't flicker on and off.
    var chainGap: TimeInterval = 0.5
    /// How far a short cue may start before its first word to reach the minimum duration.
    var maxLeadIn: TimeInterval = 0.25

    static let standard = SubtitleLayout()

    var maxCharsPerCue: Int { maxCharsPerLine * maxLines }
}

/// Words that should not end a line or a cue in Russian and English: prepositions,
/// conjunctions and particles that belong to the following word.
enum WeakWords {
    private static let words: Set<String> = [
        // Russian
        "в", "во", "на", "с", "со", "к", "ко", "о", "об", "обо", "от", "ото", "до", "по",
        "за", "из", "изо", "у", "без", "безо", "для", "над", "под", "при", "про", "через",
        "и", "а", "но", "или", "либо", "что", "чтобы", "как", "если", "когда", "не", "ни",
        // English
        "a", "an", "the", "to", "of", "in", "on", "at", "for", "and", "but", "or", "with",
        "from", "by", "as", "if", "that", "not", "my", "your", "our", "their",
    ]

    static func contains(_ word: String) -> Bool {
        let bare = word
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
        guard !bare.isEmpty else { return false }
        // A word followed by punctuation ("и," / "но —") already closes a phrase.
        if let last = word.trimmingCharacters(in: .whitespaces).last,
           last.isPunctuation || last == "—" || last == "–" { return false }
        return words.contains(bare)
    }
}

enum Punctuation {
    /// 3 = sentence end, 2 = clause break, 0 = none.
    static func strength(after word: String) -> Int {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'»”’)]"))
        guard let last = trimmed.last else { return 0 }
        if ".!?…".contains(last) { return 3 }
        if ",;:—–".contains(last) { return 2 }
        return 0
    }
}

/// Splits cue text into at most `maxLines` lines that each fit `maxCharsPerLine`,
/// preferring balanced lines that break after punctuation and never after a weak word.
enum LineBreaker {
    static func lines(for words: [String], layout: SubtitleLayout = .standard) -> [String]? {
        let words = words.filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let whole = words.joined(separator: " ")
        if whole.count <= layout.maxCharsPerLine { return [whole] }
        guard layout.maxLines >= 2, words.count >= 2 else { return nil }

        var best: (score: Double, lines: [String])?
        for split in 1..<words.count {
            let top = words[..<split].joined(separator: " ")
            let bottom = words[split...].joined(separator: " ")
            guard top.count <= layout.maxCharsPerLine, bottom.count <= layout.maxCharsPerLine else { continue }
            var score = -Double(abs(top.count - bottom.count))
            // A slightly shorter top line ("pyramid") reads more naturally.
            if top.count <= bottom.count { score += 2 }
            score += Double(Punctuation.strength(after: words[split - 1])) * 6
            if WeakWords.contains(words[split - 1]) { score -= 25 }
            if best == nil || score > best!.score { best = (score, [top, bottom]) }
        }
        return best?.lines
    }

    static func fits(_ words: [String], layout: SubtitleLayout = .standard) -> Bool {
        lines(for: words, layout: layout) != nil
    }

    /// Re-wraps existing cue text (for example after proofreading) when a line is too long.
    static func rewrapIfNeeded(_ text: String, layout: SubtitleLayout = .standard) -> String {
        let existing = text.components(separatedBy: "\n")
        if existing.count <= layout.maxLines,
           existing.allSatisfy({ $0.count <= layout.maxCharsPerLine }) {
            return text
        }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return lines(for: words, layout: layout)?.joined(separator: "\n") ?? text
    }
}
