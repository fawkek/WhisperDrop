import Foundation

enum AppText {
    static let isRussian = Locale.preferredLanguages.first?
        .lowercased()
        .hasPrefix("ru") == true

    static func pick(_ russian: String, _ english: String) -> String {
        isRussian ? russian : english
    }

    static func lineCount(_ count: Int) -> String {
        guard isRussian else { return "\(count) \(count == 1 ? "line" : "lines")" }
        let lastTwo = count % 100
        let last = count % 10
        let word: String
        if (11...14).contains(lastTwo) { word = "строк" }
        else if last == 1 { word = "строка" }
        else if (2...4).contains(last) { word = "строки" }
        else { word = "строк" }
        return "\(count) \(word)"
    }

    static func correctionCount(_ count: Int) -> String {
        guard isRussian else { return "\(count) \(count == 1 ? "correction" : "corrections")" }
        let lastTwo = count % 100
        let last = count % 10
        let word: String
        if (11...14).contains(lastTwo) { word = "исправлений" }
        else if last == 1 { word = "исправление" }
        else if (2...4).contains(last) { word = "исправления" }
        else { word = "исправлений" }
        return "\(count) \(word)"
    }
}
