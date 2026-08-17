import Foundation

struct AudioTrackOption: Identifiable, Equatable, Sendable {
    let id: Int
    let languageCode: String?
    let codec: String?
    let sampleRate: String?
    let channelLayout: String?

    var title: String {
        guard let languageCode,
              languageCode.lowercased() != "und",
              languageCode.lowercased() != "unknown" else {
            return AppText.pick("Аудиодорожка \(id + 1)", "Audio track \(id + 1)")
        }

        let normalized = Self.normalizedLanguageCode(languageCode)
        let locale = Locale(identifier: AppText.isRussian ? "ru" : "en")
        return locale.localizedString(forLanguageCode: normalized)?.capitalized
            ?? languageCode.uppercased()
    }

    var details: String {
        [formattedCodec, formattedChannels, formattedSampleRate]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var formattedCodec: String? {
        guard let codec else { return nil }
        let value = codec.lowercased()
        if value.hasPrefix("aac") { return "AAC" }
        if value.hasPrefix("ac3") { return "AC-3" }
        if value.hasPrefix("eac3") { return "E-AC-3" }
        if value.hasPrefix("dts") { return "DTS" }
        if value.hasPrefix("flac") { return "FLAC" }
        if value.hasPrefix("mp3") { return "MP3" }
        if value.hasPrefix("pcm") { return "PCM" }
        return codec.uppercased()
    }

    private var formattedChannels: String? {
        guard let channelLayout else { return nil }
        switch channelLayout.lowercased() {
        case "mono": return AppText.pick("Моно", "Mono")
        case "stereo": return AppText.pick("Стерео", "Stereo")
        default: return channelLayout
        }
    }

    private var formattedSampleRate: String? {
        guard let sampleRate else { return nil }
        let value = sampleRate.replacingOccurrences(of: " Hz", with: "")
        guard let hertz = Double(value) else { return sampleRate }
        let kilohertz = hertz / 1_000
        return kilohertz.rounded() == kilohertz
            ? "\(Int(kilohertz)) kHz"
            : "\(kilohertz.formatted(.number.precision(.fractionLength(1)))) kHz"
    }

    private static func normalizedLanguageCode(_ code: String) -> String {
        let aliases = [
            "rus": "ru", "eng": "en", "kor": "ko", "jpn": "ja",
            "ukr": "uk", "deu": "de", "ger": "de", "fra": "fr",
            "fre": "fr", "spa": "es", "ita": "it", "por": "pt",
            "zho": "zh", "chi": "zh",
        ]
        return aliases[code.lowercased()] ?? code.lowercased()
    }
}
