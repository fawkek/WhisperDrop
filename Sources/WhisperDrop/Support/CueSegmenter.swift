import Foundation

/// Builds readable subtitle cues from word-timed Whisper segments.
///
/// Whisper segments are decoding windows, not subtitles: they can run for many seconds
/// and hold far more text than fits on screen. The segmenter re-cuts the word stream so
/// every cue fits `maxLines` × `maxCharsPerLine`, lasts at most `maxDuration`, starts a
/// new cue after a pause, and breaks at sentence ends, clause punctuation or pauses
/// rather than in the middle of a phrase.
enum CueSegmenter {
    private struct Item {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
        var endsSegment: Bool
    }

    static func cues(
        from segments: [TranscribedSegment],
        layout: SubtitleLayout = .standard
    ) -> [SubtitleCue] {
        let items = makeItems(from: segments)
        var cues: [SubtitleCue] = []
        var current: [Item] = []

        func emit(_ group: [Item]) {
            guard let first = group.first, let last = group.last else { return }
            let words = group.map(\.text)
            let text = LineBreaker.lines(for: words, layout: layout)?.joined(separator: "\n")
                ?? words.joined(separator: " ")
            cues.append(SubtitleCue(start: first.start, end: max(last.end, first.start), text: text))
        }

        for item in items {
            if let last = current.last, item.start - last.end >= layout.pauseBreak {
                emit(current)
                current = []
            }
            while !current.isEmpty && !accepts(current + [item], layout: layout) {
                let split = bestSplit(current, next: item, layout: layout)
                emit(Array(current[..<split]))
                current = Array(current[split...])
            }
            current.append(item)
            if Punctuation.strength(after: item.text) == 3,
               characterCount(current) >= layout.sentenceBreakMinChars {
                emit(current)
                current = []
            }
        }
        emit(current)
        return cues
    }

    private static func accepts(_ group: [Item], layout: SubtitleLayout) -> Bool {
        guard let first = group.first, let last = group.last else { return true }
        if group.count == 1 { return true }
        guard last.end - first.start <= layout.maxDuration else { return false }
        return LineBreaker.fits(group.map(\.text), layout: layout)
    }

    /// Returns how many leading items of `current` should become the next cue.
    private static func bestSplit(_ current: [Item], next: Item, layout: SubtitleLayout) -> Int {
        var best = (score: -Double.infinity, split: current.count)
        for split in 1...current.count {
            let head = Array(current[..<split])
            let rest = Array(current[split...]) + [next]
            guard accepts(rest, layout: layout) else { continue }

            let lastWord = head[head.count - 1]
            let gapAfter = (split < current.count ? current[split].start : next.start) - lastWord.end
            let headChars = characterCount(head)

            let allWords = (current + [next]).map(\.text)
            var score = Double(Punctuation.strength(after: lastWord.text)) * 4
            score += BreakQuality.score(allWords, split: split, withinCue: false) * 1.2
            score += min(max(gapAfter, 0), 1) * 8
            if lastWord.endsSegment { score += 4 }
            score += Double(headChars) / Double(layout.maxCharsPerCue) * 6
            if headChars < 12 { score -= 15 }
            if score > best.score { best = (score, split) }
        }
        return best.split
    }

    private static func characterCount(_ group: [Item]) -> Int {
        group.map(\.text).joined(separator: " ").count
    }

    private static func makeItems(from segments: [TranscribedSegment]) -> [Item] {
        var items: [Item] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let words = segment.timedWords
            for (index, word) in words.enumerated() {
                let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let endsSegment = index == words.count - 1

                // Stray punctuation tokens attach to the previous word.
                if text.allSatisfy({ ".,!?…:;".contains($0) }), var previous = items.popLast() {
                    previous.text += text
                    previous.end = max(previous.end, word.end)
                    previous.endsSegment = previous.endsSegment || endsSegment
                    items.append(previous)
                    continue
                }

                var start = max(word.start, segment.start)
                let end = max(word.end, start)
                // Word alignment often stretches the first word after a silence back into
                // the silence; cap a word's duration so its cue doesn't appear too early.
                let longest = min(2.0, 0.5 + 0.08 * Double(text.count))
                if !word.isEstimated, end - start > longest { start = end - longest }
                if let previous = items.last, start < previous.end {
                    start = min(previous.end, end)
                }
                items.append(Item(text: text, start: start, end: end, endsSegment: endsSegment))
            }
        }
        return items
    }
}
