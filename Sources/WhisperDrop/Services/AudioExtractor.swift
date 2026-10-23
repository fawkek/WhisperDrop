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

    /// Produces audio Whisper can read: plain audio files pass through; video and
    /// selected tracks become uncompressed 16 kHz mono WAV, Whisper's native format,
    /// so the speech is not compressed a second time on the way in.
    static func prepare(
        _ source: URL,
        audioTrack: AudioTrackOption? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let directlySupported = ["wav", "mp3", "m4a", "flac", "aiff", "aif", "caf"]
        guard audioTrack != nil || !directlySupported.contains(source.pathExtension.lowercased()) else { return source }

        if let audioTrack, ffmpegExecutable != nil {
            return try await prepareWithFFmpeg(source, audioTrack: audioTrack, progress: progress)
        }
        do {
            return try await exportPCM(source, audioTrackIndex: audioTrack?.id ?? 0, progress: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppFileLog.write("AVFoundation audio extraction failed, trying ffmpeg: \(error.localizedDescription)")
            return try await prepareWithFFmpeg(source, audioTrack: audioTrack, progress: progress)
        }
    }

    /// Decodes one audio track with AVFoundation into a 16 kHz mono 16-bit WAV.
    private static func exportPCM(
        _ source: URL,
        audioTrackIndex: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.indices.contains(audioTrackIndex) else {
            throw ExtractionError(details: AppText.pick(
                tracks.isEmpty ? "В файле не найдена аудиодорожка." : "Выбранная аудиодорожка больше недоступна.",
                tracks.isEmpty ? "No audio track was found in the file." : "The selected audio track is no longer available."
            ))
        }
        let duration = max(0.001, CMTimeGetSeconds(try await asset.load(.duration)))

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = FileManager.default.temporaryDirectory
            .appending(path: "WhisperDrop-\(UUID().uuidString).wav")
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderAudioMixOutput(audioTracks: [tracks[audioTrackIndex]], audioSettings: settings)
        guard reader.canAdd(readerOutput) else { throw ExtractionError(details: "AVAssetReader") }
        reader.add(readerOutput)
        let writer = try AVAssetWriter(outputURL: output, fileType: .wav)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw ExtractionError(details: "AVAssetWriter") }
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else {
            throw reader.error ?? writer.error ?? CocoaError(.fileReadUnknown)
        }
        writer.startSession(atSourceTime: .zero)
        do {
            while let buffer = readerOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard input.append(buffer) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
                if seconds.isFinite { progress(min(1, seconds / duration)) }
            }
            guard reader.status == .completed else { throw reader.error ?? CocoaError(.fileReadUnknown) }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        progress(1)
        return output
    }

    private static func prepareWithFFmpeg(
        _ source: URL,
        audioTrack: AudioTrackOption?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let executable = ffmpegExecutable else {
            throw ExtractionError(details: AppText.pick(
                "Для файлов MKV требуется FFmpeg.",
                "FFmpeg is required for MKV files."
            ))
        }

        let output = FileManager.default.temporaryDirectory
            .appending(path: "WhisperDrop-\(UUID().uuidString).wav")
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
        process.arguments = ffmpegArguments(
            source: source,
            output: output,
            audioTrackIndex: audioTrack?.id ?? 0,
            channelLayout: audioTrack?.channelLayout
        )
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

        do {
            let file = try AVAudioFile(forReading: output)
            guard file.length > 0 else { throw CocoaError(.fileReadCorruptFile) }
        } catch {
            try? FileManager.default.removeItem(at: output)
            AppFileLog.write("Core Audio validation failed after FFmpeg extraction: \(error.localizedDescription)")
            throw ExtractionError(details: AppText.pick(
                "Подготовленная аудиодорожка не читается macOS.",
                "The prepared audio track cannot be read by macOS."
            ))
        }

        AppFileLog.write("FFmpeg audio extraction succeeded: \(source.lastPathComponent), audioTrack=\(audioTrack?.id ?? 0)")
        progress(1)
        return output
    }

    /// 16 kHz mono PCM WAV. Surround tracks (5.1, 7.1) are mixed with the centre channel
    /// in front, where film dialogue lives, so music and effects compete less with speech.
    static func ffmpegArguments(
        source: URL,
        output: URL,
        audioTrackIndex: Int,
        channelLayout: String? = nil
    ) -> [String] {
        var arguments = [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-i", source.path,
            "-map", "0:a:\(audioTrackIndex)", "-vn",
        ]
        let layout = channelLayout?.lowercased() ?? ""
        if layout.hasPrefix("5.1") || layout.hasPrefix("7.1") {
            arguments += ["-af", "pan=mono|c0=0.6*FC+0.2*FL+0.2*FR"]
        } else {
            arguments += ["-ac", "1"]
        }
        arguments += ["-ar", "16000", "-c:a", "pcm_s16le", output.path]
        return arguments
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
