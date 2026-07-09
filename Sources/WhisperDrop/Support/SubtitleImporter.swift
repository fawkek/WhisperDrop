import Foundation

enum SubtitleImportError: LocalizedError {
    case unsupportedFormat
    case unreadableText
    case noCues

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            AppText.pick("Этот формат субтитров пока не поддерживается.", "This subtitle format is not supported yet.")
        case .unreadableText:
            AppText.pick("Не удалось прочитать текст субтитров.", "Couldn’t read subtitle text.")
        case .noCues:
            AppText.pick("В файле не найдены субтитры.", "No subtitle cues were found in the file.")
        }
    }
}

enum SubtitleImporter {
    static func isSubtitleFile(_ url: URL) -> Bool {
        ["srt", "vtt", "webvtt", "txt", "ass"].contains(url.pathExtension.lowercased())
    }

    static func format(for url: URL) -> SubtitleFormat {
        switch url.pathExtension.lowercased() {
        case "vtt", "webvtt": .vtt
        case "ass": .ass
        case "txt": .txt
        default: .srt
        }
    }

    static func load(_ url: URL) throws -> [SubtitleCue] {
        let text = try readText(url)
        let cues: [SubtitleCue]
        switch url.pathExtension.lowercased() {
        case "srt":
            cues = parseTimedBlocks(text)
        case "vtt", "webvtt":
            cues = parseTimedBlocks(text.replacingOccurrences(of: "WEBVTT", with: ""))
        case "ass":
            cues = parseASS(text)
        case "txt":
            cues = parsePlainText(text)
        default:
            throw SubtitleImportError.unsupportedFormat
        }
        let cleaned = cues
            .map { SubtitleCue(start: $0.start, end: $0.end, text: WhisperTextSanitizer.clean($0.text)) }
            .filter { !$0.text.isEmpty && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !cleaned.isEmpty else { throw SubtitleImportError.noCues }
        return cleaned
    }

    private static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [
            .utf8,
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .windowsCP1251,
            .windowsCP1252
        ]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
                    .replacingOccurrences(of: "\u{FEFF}", with: "")
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
            }
        }
        throw SubtitleImportError.unreadableText
    }

    private static func parseTimedBlocks(_ text: String) -> [SubtitleCue] {
        text.components(separatedBy: "\n\n").compactMap { block in
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count >= 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]) else { return nil }
            let text = lines.dropFirst(timeIndex + 1).joined(separator: "\n")
            return SubtitleCue(start: start, end: end, text: text)
        }
    }

    private static func parseASS(_ text: String) -> [SubtitleCue] {
        text.split(separator: "\n").compactMap { rawLine in
            let line = String(rawLine)
            guard line.hasPrefix("Dialogue:") else { return nil }
            let fields = line.components(separatedBy: ",")
            guard fields.count >= 10,
                  let start = parseTimestamp(fields[1]),
                  let end = parseTimestamp(fields[2]) else { return nil }
            let cueText = fields.dropFirst(9)
                .joined(separator: ",")
                .replacingOccurrences(of: #"\\N"#, with: "\n")
                .replacingOccurrences(of: #"\N"#, with: "\n")
            return SubtitleCue(start: start, end: end, text: cueText)
        }
    }

    private static func parsePlainText(_ text: String) -> [SubtitleCue] {
        text.split(separator: "\n").enumerated().compactMap { index, line in
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            let start = TimeInterval(index * 3)
            return SubtitleCue(start: start, end: start + 3, text: cleaned)
        }
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: " \t")).first ?? raw
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }
        let secondsPart = parts.last ?? "0"
        let seconds = Double(secondsPart) ?? 0
        let minutes = Double(parts.dropLast().last ?? "0") ?? 0
        let hours = parts.count >= 3 ? (Double(parts.dropLast(2).last ?? "0") ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
    }
}
