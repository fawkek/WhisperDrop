import Foundation

enum SubtitleFormat: String, CaseIterable, Codable, Identifiable {
    case srt
    case vtt
    case ass
    case txt

    var id: Self { self }
    var title: String {
        switch self {
        case .srt: "SRT"
        case .vtt: "WebVTT"
        case .ass: "ASS"
        case .txt: "TXT"
        }
    }
    var fileExtension: String { rawValue }
    var requiresUTF8: Bool { self == .vtt }
}

enum SubtitleEncoding: String, CaseIterable, Codable, Identifiable {
    case utf8
    case utf8BOM
    case utf16LE
    case windows1251
    case windows1252

    var id: Self { self }
    var title: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf8BOM: "UTF-8 BOM"
        case .utf16LE: "UTF-16 LE"
        case .windows1251: "Windows-1251"
        case .windows1252: "Windows-1252"
        }
    }
}
