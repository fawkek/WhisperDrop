import Foundation

/// Starts the GUI, or a headless developer mode for checking subtitle quality:
///
///     WhisperDrop --transcribe <media> <out.srt> [--segments <segments.json>]
///     WhisperDrop --resegment <segments.json> <out.srt>
///
/// `--segments` saves Whisper's raw output so segmentation rules can be re-checked
/// with `--resegment` in a second, without running the model again.
@main
enum Entry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--snapshots", arguments.count >= 2 {
            MainActor.assumeIsolated { Snapshots.render(to: URL(filePath: arguments[1])) }
            exit(0)
        }
        guard let mode = arguments.first, mode == "--transcribe" || mode == "--resegment" else {
            WhisperDropApp.main()
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0
        Task.detached {
            do {
                try await DeveloperCommands.run(arguments)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exitCode = 1
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(exitCode)
    }
}

enum DeveloperCommands {
    struct UsageError: LocalizedError {
        var errorDescription: String? {
            "usage: WhisperDrop --transcribe <media> <out.srt> [--segments <segments.json>] | --resegment <segments.json> <out.srt>"
        }
    }

    static func run(_ arguments: [String]) async throws {
        guard arguments.count >= 3 else { throw UsageError() }
        let input = URL(filePath: arguments[1])
        let output = URL(filePath: arguments[2])

        let segments: [TranscribedSegment]
        if arguments[0] == "--resegment" {
            segments = try JSONDecoder().decode([TranscribedSegment].self, from: Data(contentsOf: input))
        } else {
            let audio = try await AudioExtractor.prepare(input) { _ in }
            defer { if audio != input { try? FileManager.default.removeItem(at: audio) } }
            let started = Date()
            segments = try await TranscriptionService().transcribeSegments(file: audio) { _ in }
            print(String(format: "transcribed in %.1fs: %d segments", Date().timeIntervalSince(started), segments.count))
            if let index = arguments.firstIndex(of: "--segments"), index + 1 < arguments.count {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(segments).write(to: URL(filePath: arguments[index + 1]))
            }
        }

        let cues = TranscriptionService.cues(from: segments)
        try Data(SubtitleExporter.render(cues, format: .srt).utf8).write(to: output, options: .atomic)
        print("wrote \(cues.count) cues to \(output.path)")
    }
}
