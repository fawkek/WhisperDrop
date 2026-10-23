import Foundation

/// Makes cue timing comfortable to read without moving cues away from their speech:
/// no overlaps, a small gap between cues, a short tail after the last word, enough time
/// on screen for the text length, and no sub-half-second gaps that make cues flicker.
enum CueTimingNormalizer {
    static func normalize(
        _ input: [SubtitleCue],
        layout: SubtitleLayout = .standard
    ) -> [SubtitleCue] {
        var cues = input
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
            .map { Timing(start: max(0, $0.start), end: max(0, $0.end), text: $0.text) }
        guard !cues.isEmpty else { return [] }

        for index in cues.indices {
            let nextStart = index + 1 < cues.count ? cues[index + 1].start : .infinity
            let previousEnd = index > 0 ? cues[index - 1].end : -Double.infinity
            var cue = cues[index]
            let limit = nextStart - layout.minGap

            // Tail after the last word.
            cue.end = min(max(cue.end, cue.start) + layout.tail, max(limit, cue.end))

            // Enough time to read the text.
            let readable = Double(cue.text.count) / layout.maxCharsPerSecond
            let required = min(layout.maxDuration, max(layout.minDuration, readable))
            if cue.end - cue.start < required {
                cue.end = max(cue.end, min(cue.start + required, limit))
            }
            if cue.end - cue.start < required {
                let earliest = max(previousEnd + layout.minGap, cue.start - layout.maxLeadIn, 0)
                cue.start = max(earliest, min(cue.start, cue.end - required))
            }

            // Close small gaps so the next cue replaces this one without a blink.
            if nextStart - cue.end < layout.chainGap, nextStart.isFinite {
                cue.end = max(cue.end, limit)
            }

            // Never overlap the next cue.
            if cue.end > limit { cue.end = limit }
            cue.end = min(cue.end, cue.start + layout.maxDuration)
            cues[index] = cue

            // A cue squeezed to almost nothing by an early next cue pushes that cue back.
            let minimumVisible = 0.3
            if cue.end - cue.start < minimumVisible, index + 1 < cues.count {
                cues[index].end = cue.start + minimumVisible
                let pushed = cues[index].end + layout.minGap
                cues[index + 1].start = pushed
                cues[index + 1].end = max(cues[index + 1].end, pushed + minimumVisible)
            }
        }

        return cues.map { SubtitleCue(start: $0.start, end: $0.end, text: $0.text) }
    }

    private struct Timing {
        var start: TimeInterval
        var end: TimeInterval
        var text: String
    }
}
