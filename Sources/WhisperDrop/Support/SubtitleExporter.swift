import Foundation

enum SubtitleExportError: LocalizedError {
    case unsupportedCharacters(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedCharacters(encoding):
            AppText.pick(
                "Некоторые символы нельзя сохранить в кодировке \(encoding). Выберите UTF-8.",
                "Some characters cannot be saved as \(encoding). Choose UTF-8."
            )
        }
    }
}

enum SubtitleExporter {
    static func render(_ cues: [SubtitleCue], format: SubtitleFormat) -> String {
        switch format {
        case .srt: SRTFormatter.render(cues)
        case .vtt: renderVTT(cues)
        case .ass: renderASS(cues)
        case .txt: cues.map { WhisperTextSanitizer.clean($0.text) }.joined(separator: "\n") + "\n"
        }
    }

    static func data(_ text: String, encoding: SubtitleEncoding) throws -> Data {
        let stringEncoding: String.Encoding
        let prefix: [UInt8]
        switch encoding {
        case .utf8:
            stringEncoding = .utf8
            prefix = []
        case .utf8BOM:
            stringEncoding = .utf8
            prefix = [0xEF, 0xBB, 0xBF]
        case .utf16LE:
            stringEncoding = .utf16LittleEndian
            prefix = [0xFF, 0xFE]
        case .windows1251:
            stringEncoding = .windowsCP1251
            prefix = []
        case .windows1252:
            stringEncoding = .windowsCP1252
            prefix = []
        }
        guard let encoded = text.data(using: stringEncoding, allowLossyConversion: false) else {
            throw SubtitleExportError.unsupportedCharacters(encoding.title)
        }
        return Data(prefix) + encoded
    }

    private static func renderVTT(_ cues: [SubtitleCue]) -> String {
        let body = cues.map { cue in
            "\(vttTimestamp(cue.start)) --> \(vttTimestamp(cue.end))\n\(WhisperTextSanitizer.clean(cue.text))"
        }.joined(separator: "\n\n")
        return "WEBVTT\n\n\(body)\n"
    }

    private static func renderASS(_ cues: [SubtitleCue]) -> String {
        let header = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 1920
        PlayResY: 1080

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,54,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,0,2,40,40,36,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """
        let events = cues.map { cue in
            let text = WhisperTextSanitizer.clean(cue.text).replacingOccurrences(of: "\n", with: #"\N"#)
            return "Dialogue: 0,\(assTimestamp(cue.start)),\(assTimestamp(cue.end)),Default,,0,0,0,,\(text)"
        }.joined(separator: "\n")
        return header + "\n" + events + "\n"
    }

    private static func vttTimestamp(_ seconds: TimeInterval) -> String {
        SRTFormatter.timestamp(seconds).replacingOccurrences(of: ",", with: ".")
    }

    private static func assTimestamp(_ seconds: TimeInterval) -> String {
        let centiseconds = max(0, Int((seconds * 100).rounded()))
        return String(
            format: "%d:%02d:%02d.%02d",
            centiseconds / 360_000,
            centiseconds % 360_000 / 6_000,
            centiseconds % 6_000 / 100,
            centiseconds % 100
        )
    }
}
