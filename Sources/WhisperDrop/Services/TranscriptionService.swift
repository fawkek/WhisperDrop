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
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: nil,
            temperature: 0,
            detectLanguage: true,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        let results: [TranscriptionResult] = try await engine.transcribe(
            audioPath: file.path,
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
        return discovered.map(Self.segment)
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
