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
        return discovered
            .sorted { $0.start < $1.start }
            .compactMap { segment in
                let text = WhisperTextSanitizer.clean(segment.text)
                guard !text.isEmpty, segment.end > segment.start else { return nil }
                return SubtitleCue(start: Double(segment.start), end: Double(segment.end), text: text)
            }
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
