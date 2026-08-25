import Foundation

enum SubtitleHallucinationFilter {
    private static let exactPhrases: Set<String> = [
        "девушки отдыхают",
        "girls are relaxing",
    ]

    private static let creditPrefixes = [
        "субтитры сделал дима торжок",
        "субтитры делал дима торжок",
        "subtitles by dima torzhok",
    ]

    static func clean(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        cues.filter { !isKnownHallucination($0.text) }
    }

    static func isKnownHallucination(_ text: String) -> Bool {
        let value = normalized(text)
        guard !value.isEmpty else { return true }
        return exactPhrases.contains(value)
            || creditPrefixes.contains(where: value.hasPrefix)
    }

    private static func normalized(_ text: String) -> String {
        let folded = text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
        let words = folded.unicodeScalars.split { scalar in
            !CharacterSet.alphanumerics.contains(scalar)
        }
        return words.map(String.init).joined(separator: " ")
    }
}
