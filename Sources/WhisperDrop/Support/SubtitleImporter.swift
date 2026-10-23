import Foundation

enum SubtitleImportError: LocalizedError {
    case unsupportedFormat
    case unreadableText
    case noCues
    case plainTextWithoutTimecodes

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            AppText.pick("Этот формат субтитров пока не поддерживается.", "This subtitle format is not supported yet.")
        case .unreadableText:
            AppText.pick("Не удалось прочитать текст субтитров.", "Couldn’t read subtitle text.")
        case .noCues:
            AppText.pick("В файле не найдены субтитры.", "No subtitle cues were found in the file.")
        case .plainTextWithoutTimecodes:
            AppText.pick(
                "В текстовом файле нет таймкодов. Перетащите видео или аудио, чтобы создать субтитры, либо файл SRT, VTT или ASS.",
                "This text file has no timecodes. Drop a video or audio file to create subtitles, or an SRT, VTT, or ASS file."
            )
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
                .map { SubtitleCue(start: $0.start, end: $0.end, text: cleanVTTMarkup($0.text)) }
        case "ass":
            cues = parseASS(text)
        case "txt":
            // A .txt is subtitles only when it carries SRT-style timecodes; plain text
            // would get invented timings.
            guard text.contains("-->") else { throw SubtitleImportError.plainTextWithoutTimecodes }
            cues = parseTimedBlocks(text)
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
        guard let text = decode(try Data(contentsOf: url)) else { throw SubtitleImportError.unreadableText }
        return text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Picks the text encoding: a BOM first, then UTF-16 recognised by its zero bytes,
    /// then UTF-8, then Windows-1251 for Cyrillic-heavy text or Windows-1252 otherwise.
    /// UTF-16 is never guessed without evidence: it "decodes" almost any byte sequence.
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if bytes.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        if bytes.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        let sample = bytes.prefix(4_096)
        if sample.count >= 4 {
            let evenZeros = stride(from: 0, to: sample.count, by: 2).filter { sample[sample.startIndex + $0] == 0 }.count
            let oddZeros = stride(from: 1, to: sample.count, by: 2).filter { sample[sample.startIndex + $0] == 0 }.count
            let half = Double(sample.count / 2)
            if Double(oddZeros) > half * 0.3, let text = String(data: data, encoding: .utf16LittleEndian) { return text }
            if Double(evenZeros) > half * 0.3, let text = String(data: data, encoding: .utf16BigEndian) { return text }
        }
        // Real text has no NUL bytes, so UTF-8 is checked after the UTF-16 test.
        if let text = String(data: data, encoding: .utf8) { return text }

        // Russian text in Windows-1251 is mostly high bytes; Western text in
        // Windows-1252 is mostly ASCII letters with an occasional accent.
        let high = bytes.filter { $0 >= 0x80 }.count
        let asciiLetters = bytes.filter { (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) }.count
        let cyrillicLikely = Double(high) / Double(max(1, high + asciiLetters)) > 0.4
        return String(data: data, encoding: cyrillicLikely ? .windowsCP1251 : .windowsCP1252)
    }

    /// Removes WebVTT voice/class/timestamp tags and decodes its character entities.
    static func cleanVTTMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
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
                // Style overrides such as {\\i1} or {\\pos(…)} are formatting, not text.
                .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\\N"#, with: "\n")
                .replacingOccurrences(of: #"\N"#, with: "\n")
                .replacingOccurrences(of: #"\n"#, with: "\n")
                .replacingOccurrences(of: #"\h"#, with: " ")
            return SubtitleCue(start: start, end: end, text: cueText)
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
