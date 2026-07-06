import Foundation

struct SubtitleCue: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

