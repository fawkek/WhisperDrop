@preconcurrency import AVFoundation
import Foundation

enum AudioExtractor {
    private struct ExtractionError: LocalizedError {
        let details: String

        var errorDescription: String? {
            AppText.pick(
                "Не удалось извлечь аудио из видео. \(details)",
                "Could not extract audio from the video. \(details)"
            )
        }
    }

    static func audioTracks(in source: URL) async throws -> [AudioTrackOption] {
        if let executable = ffmpegExecutable {
            do {
                let metadata = try await ffmpegMetadata(for: source, executable: executable)
                let tracks = parseAudioTracks(from: metadata)
                if !tracks.isEmpty { return tracks }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppFileLog.write("FFmpeg audio probe failed, trying AVFoundation: \(error.localizedDescription)")
            }
        }

        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            throw ExtractionError(details: AppText.pick(
                "В файле не найдена аудиодорожка.",
                "No audio track was found in the file."
            ))
        }
        return tracks.indices.map {
            AudioTrackOption(id: $0, languageCode: nil, codec: nil, sampleRate: nil, channelLayout: nil)
        }
    }

    static func prepare(
        _ source: URL,
        audioTrack: AudioTrackOption? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let directlySupported = ["wav", "mp3", "m4a", "flac", "aiff", "aif", "caf"]
        guard audioTrack != nil || !directlySupported.contains(source.pathExtension.lowercased()) else { return source }

        if let audioTrack {
            if ffmpegExecutable != nil {
                return try await prepareWithFFmpeg(source, audioTrackIndex: audioTrack.id, progress: progress)
            }
            return try await prepareSelectedTrackWithAVFoundation(
                source,
                audioTrackIndex: audioTrack.id,
                progress: progress
            )
        }

        let output = FileManager.default.temporaryDirectory
            .appending(path: "WhisperDrop-\(UUID().uuidString).m4a")
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return try await prepareWithFFmpeg(source, audioTrackIndex: 0, progress: progress)
        }

        let observer = Task {
            while !Task.isCancelled {
                progress(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        defer { observer.cancel() }

        exporter.outputURL = output
        exporter.outputFileType = .m4a
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    exporter.exportAsynchronously {
                        switch exporter.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        case .failed:
                            continuation.resume(throwing: exporter.error ?? CocoaError(.fileReadUnknown))
                        default:
                            continuation.resume(throwing: exporter.error ?? CocoaError(.fileReadUnknown))
                        }
                    }
                }
            } onCancel: {
                exporter.cancelExport()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: output)
            AppFileLog.write("AVFoundation audio extraction failed, trying ffmpeg: \(error.localizedDescription)")
            return try await prepareWithFFmpeg(source, audioTrackIndex: 0, progress: progress)
        }
        progress(1)
        return output
    }

    private static func prepareSelectedTrackWithAVFoundation(
        _ source: URL,
        audioTrackIndex: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.indices.contains(audioTrackIndex) else {
            throw ExtractionError(details: AppText.pick(
                "Выбранная аудиодорожка больше недоступна.",
                "The selected audio track is no longer available."
            ))
        }

        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExtractionError(details: AppText.pick(
                "Не удалось подготовить выбранную дорожку.",
                "Could not prepare the selected track."
            ))
        }
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: tracks[audioTrackIndex],
            at: .zero
        )

        let output = FileManager.default.temporaryDirectory
            .appending(path: "WhisperDrop-\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExtractionError(details: AppText.pick(
                "Не удалось создать аудиофайл выбранной дорожки.",
                "Could not create an audio file for the selected track."
            ))
        }

        let observer = Task {
            while !Task.isCancelled {
                progress(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        defer { observer.cancel() }

        exporter.outputURL = output
        exporter.outputFileType = .m4a
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(throwing: exporter.error ?? CocoaError(.fileReadUnknown))
                    }
                }
            }
        } onCancel: {
            exporter.cancelExport()
        }
        progress(1)
        return output
    }

    private static func prepareWithFFmpeg(
        _ source: URL,
        audioTrackIndex: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let executable = ffmpegExecutable else {
            throw ExtractionError(details: AppText.pick(
                "Для файлов MKV требуется FFmpeg.",
                "FFmpeg is required for MKV files."
            ))
        }

        let output = FileManager.default.temporaryDirectory
            .appending(path: "WhisperDrop-\(UUID().uuidString).m4a")
        let process = Process()
        let errorURL = FileManager.default.temporaryDirectory
            .appending(path: "WhisperDrop-ffmpeg-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorFile = try FileHandle(forWritingTo: errorURL)
        defer {
            try? errorFile.close()
            try? FileManager.default.removeItem(at: errorURL)
        }
        process.executableURL = executable
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-i", source.path,
            "-map", "0:a:\(audioTrackIndex)", "-vn",
            "-c:a", "aac", "-b:a", "128k",
            output.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorFile
        progress(0.01)

        do {
            try process.run()
        } catch {
            throw ExtractionError(details: error.localizedDescription)
        }

        do {
            try await waitForTermination(of: process)
            try Task.checkCancellation()
        } catch {
            if process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(at: output)
            throw error
        }

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: output.path) else {
            try? errorFile.synchronize()
            let data = (try? Data(contentsOf: errorURL)) ?? Data()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: output)
            throw ExtractionError(details: message.isEmpty
                ? AppText.pick("FFmpeg завершился с ошибкой.", "FFmpeg failed.")
                : message)
        }

        AppFileLog.write("FFmpeg audio extraction succeeded: \(source.lastPathComponent), audioTrack=\(audioTrackIndex)")
        progress(1)
        return output
    }

    private static var ffmpegExecutable: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appending(path: "FFmpegRuntime/ffmpeg"),
            URL(filePath: "/opt/homebrew/bin/ffmpeg"),
            URL(filePath: "/usr/local/bin/ffmpeg"),
        ].compactMap { $0 }
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private static func ffmpegMetadata(for source: URL, executable: URL) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "WhisperDrop-probe-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputFile = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputFile.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-hide_banner", "-nostdin", "-i", source.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = outputFile

        try process.run()
        do {
            try await waitForTermination(of: process)
            try Task.checkCancellation()
        } catch {
            if process.isRunning { process.terminate() }
            throw error
        }

        try? outputFile.synchronize()
        let data = try Data(contentsOf: outputURL)
        return String(decoding: data, as: UTF8.self)
    }

    private static func waitForTermination(of process: Process) async throws {
        await withTaskCancellationHandler {
            await Task.detached { process.waitUntilExit() }.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    static func parseAudioTracks(from metadata: String) -> [AudioTrackOption] {
        let pattern = #"Stream #\d+:\d+(?:\[[^\]]+\])?(?:\(([^)]+)\))?: Audio: ([^,\n]+)(?:, ([^,\n]+))?(?:, ([^,\n]+))?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(metadata.startIndex..., in: metadata)

        return expression.matches(in: metadata, range: range).enumerated().map { index, match in
            func capture(_ number: Int) -> String? {
                let range = match.range(at: number)
                guard range.location != NSNotFound,
                      let swiftRange = Range(range, in: metadata) else { return nil }
                let value = metadata[swiftRange].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }

            return AudioTrackOption(
                id: index,
                languageCode: capture(1),
                codec: capture(2),
                sampleRate: capture(3),
                channelLayout: capture(4)
            )
        }
    }
}
