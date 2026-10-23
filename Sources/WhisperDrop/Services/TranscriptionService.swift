import AVFoundation
import Foundation
import WhisperKit

actor TranscriptionService {
    private var whisperKit: WhisperKit?

    func downloadModel(progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws {
        try await ModelDownloader.download { downloadedBytes, totalBytes in
            progress(ModelDownloadProgress(
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes
            ))
        }
    }

    func transcribe(
        file: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [SubtitleCue] {
        Self.cues(from: try await transcribeSegments(file: file, progress: progress))
    }

    /// Raw Whisper segments with word timings and quality metrics.
    func transcribeSegments(
        file: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscribedSegment] {
        let engine = try await engine()
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
        try Task.checkCancellation()

        // One language for the whole file. Detecting it in every 30-second window lets
        // a noisy window flip into another language and come out translated.
        let language = try await detectLanguage(samples, engine: engine)
        AppFileLog.write("Speech language: \(language ?? "auto")")
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            detectLanguage: language == nil,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        let results: [TranscriptionResult] = try await engine.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: { update in
                let fraction = engine.progress.fractionCompleted
                if fraction.isFinite {
                    progress(min(0.98, max(0, fraction)))
                }
                return true
            }
        )
        var discovered: [TranscriptionSegment] = []
        for result in results { discovered.append(contentsOf: result.segments) }
        progress(1)
        let duration = Double(samples.count) / 16_000
        return Self.clamped(discovered.map(Self.segment), toDuration: duration)
    }

    /// Whisper sometimes reports a segment past the end of the audio (seen on trailing
    /// silence); such text can't belong to anything that was said.
    static func clamped(_ segments: [TranscribedSegment], toDuration duration: TimeInterval) -> [TranscribedSegment] {
        segments.compactMap { segment in
            guard segment.start < duration - 0.05 else { return nil }
            var copy = segment
            copy.end = min(segment.end, duration)
            copy.words = segment.words
                .filter { $0.start < duration }
                .map { word in
                    var word = word
                    word.end = min(word.end, duration)
                    return word
                }
            return copy
        }
    }

    /// Votes over up to three speech-heavy 30-second windows (start, middle, end).
    private func detectLanguage(_ samples: [Float], engine: WhisperKit) async throws -> String? {
        let window = 30 * 16_000
        var votes: [String: (count: Int, best: Float)] = [:]
        for start in Self.languageProbeStarts(samples) {
            try Task.checkCancellation()
            let slice = Array(samples[start..<min(samples.count, start + window)])
            guard let result = try? await engine.detectLangauge(audioArray: slice) else { continue }
            let probability = result.langProbs[result.language] ?? 0
            let previous = votes[result.language] ?? (0, -.infinity)
            votes[result.language] = (previous.count + 1, max(previous.best, probability))
        }
        return votes.max { a, b in
            a.value.count != b.value.count ? a.value.count < b.value.count : a.value.best < b.value.best
        }?.key
    }

    /// Start samples of the windows used for language detection: windows where at least
    /// a few seconds rise above the file's quiet floor, taken from the start, middle and end.
    static func languageProbeStarts(_ samples: [Float], sampleRate: Int = 16_000) -> [Int] {
        let second = sampleRate
        let window = 30 * sampleRate
        guard samples.count > second else { return [0] }
        let rms: [Float] = stride(from: 0, to: samples.count - second + 1, by: second).map { start in
            var sum: Float = 0
            for index in start..<(start + second) { sum += samples[index] * samples[index] }
            return (sum / Float(second)).squareRoot()
        }
        let sorted = rms.sorted()
        let floor = sorted[sorted.count / 5]
        let threshold = max(0.01, floor * 3)
        let candidates = stride(from: 0, to: max(1, samples.count - window / 2), by: window).filter { start in
            let first = start / second
            let last = min(rms.count, first + 30)
            return first < last && rms[first..<last].filter { $0 > threshold }.count >= 5
        }
        guard !candidates.isEmpty else { return [0] }
        var picks = [candidates[0], candidates[candidates.count / 2], candidates[candidates.count - 1]]
        picks = picks.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        return picks
    }

    /// Whisper segments → cleaned, readable, well-timed subtitle cues.
    static func cues(
        from segments: [TranscribedSegment],
        layout: SubtitleLayout = .standard
    ) -> [SubtitleCue] {
        let usable = segments.filter {
            $0.end > $0.start && !WhisperTextSanitizer.clean($0.text).isEmpty
        }
        let cleaned = SubtitleHallucinationFilter.clean(segments: usable)
        let removed = usable.count - cleaned.count
        if removed > 0 { AppFileLog.write("Removed likely hallucinated segments: \(removed)") }
        let cues = CueSegmenter.cues(from: cleaned, layout: layout)
        return CueTimingNormalizer.normalize(cues, layout: layout)
    }

    private static func segment(_ segment: TranscriptionSegment) -> TranscribedSegment {
        TranscribedSegment(
            start: Double(segment.start),
            end: Double(segment.end),
            text: segment.text,
            words: (segment.words ?? []).map {
                TranscribedWord(
                    text: $0.word,
                    start: Double($0.start),
                    end: Double($0.end),
                    probability: Double($0.probability)
                )
            },
            avgLogprob: Double(segment.avgLogprob),
            compressionRatio: Double(segment.compressionRatio),
            noSpeechProb: Double(segment.noSpeechProb)
        )
    }

    private func engine() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        let config = WhisperKitConfig(
            modelFolder: ModelLocator.modelFolder.path,
            tokenizerFolder: ModelLocator.tokenizerFolder,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        let created = try await WhisperKit(config)
        whisperKit = created
        return created
    }
}
