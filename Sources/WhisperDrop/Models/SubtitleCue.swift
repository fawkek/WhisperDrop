import Foundation

struct SubtitleCue: Codable, Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}
