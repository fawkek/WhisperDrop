import AppKit
import Foundation

/// Keeps the small proofreading model honest: a correction is accepted only when it is
/// the kind of change it was asked for. Viewers who rely on subtitles can't hear a word
/// the model swapped for another, so anything bigger keeps the original text.
///
/// A word may only change when the original is misspelled and the replacement is a real
/// word (checked by the system spell checker), and only by a few letters. A correctly
/// spelled word is never touched, so the model can't turn "короткий фильм" into
/// "короткие фильмы" or "рыбак" into "рыбки".
enum ProofreadingGuard {
    static func accept(
        original: String,
        corrected: String,
        isRealWord: (String) -> Bool
    ) -> String {
        let candidate = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return original }

        let before = words(original)
        let after = words(candidate)
        // Only punctuation, capitalisation or spacing changed.
        if before == after { return candidate }
        // Joining or splitting words is fine only when nothing but the spaces moved.
        guard before.count == after.count else {
            return before.joined() == after.joined() ? candidate : original
        }
        for (x, y) in zip(before, after) where x != y {
            guard !isRealWord(x), isRealWord(y) else { return original }
            // A swapped letter pair costs two edits; short words get one.
            let limit = x.count <= 3 ? 1 : max(2, Int((Double(x.count) * 0.4).rounded(.down)))
            if distance(Array(x), Array(y)) > limit { return original }
        }
        return candidate
    }

    /// Lower-cased words without punctuation; "ё" counts as "е".
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Levenshtein distance.
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

/// The system spell checker, used to tell typos from real words.
@MainActor
enum SpellCheck {
    static func isRealWord(_ word: String) -> Bool {
        guard word.count > 1, !word.allSatisfy(\.isNumber) else { return true }
        let language = word.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } ? "ru" : "en"
        let checker = NSSpellChecker.shared
        guard checker.availableLanguages.contains(language) else { return true }
        let range = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }
}
