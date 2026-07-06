import AVFoundation
import Foundation
import WhisperKit

actor TranscriptionService {
    private var whisperKit: WhisperKit?

    func downloadModel(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: ModelLocator.modelsRoot, withIntermediateDirectories: true)
        let downloaded = try await WhisperKit.download(
            variant: "large-v3-v20240930_626MB",
            downloadBase: ModelLocator.modelsRoot,
            progressCallback: { value in progress(value.fractionCompleted) }
        )
        if downloaded.standardizedFileURL != ModelLocator.modelFolder.standardizedFileURL {
            if FileManager.default.fileExists(atPath: ModelLocator.modelFolder.path) {
                try FileManager.default.removeItem(at: ModelLocator.modelFolder)
            }
            try FileManager.default.copyItem(at: downloaded, to: ModelLocator.modelFolder)
        }
    }

    func transcribe(
        file: URL,
        duration: TimeInterval,
        progress: @escaping @Sendable (Double) -> Void,
        lineCount: @escaping @Sendable (Int) -> Void
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
        var discoveredCount = 0
        engine.segmentDiscoveryCallback = { segments in
            discoveredCount += segments.count
            lineCount(discoveredCount)
        }
        let results: [TranscriptionResult] = try await engine.transcribe(
            audioPath: file.path,
            decodeOptions: options,
            callback: { update in
                let decoded = update.timings.inputAudioSeconds
                if duration > 0 { progress(min(0.98, decoded / duration)) }
                return true
            }
        )
        engine.segmentDiscoveryCallback = nil
        let finalCount = results.reduce(0) { $0 + $1.segments.count }
        lineCount(finalCount)
        var discovered: [TranscriptionSegment] = []
        for result in results { discovered.append(contentsOf: result.segments) }
        progress(1)
        return discovered
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
            .sorted { $0.start < $1.start }
            .map { SubtitleCue(start: Double($0.start), end: Double($0.end), text: $0.text) }
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
