import Foundation

/// Starts the GUI, or a headless developer mode for checking subtitle quality:
///
///     WhisperDrop --transcribe <media> <out.srt> [--segments <segments.json>]
///     WhisperDrop --resegment <segments.json> <out.srt>
///     WhisperDrop --proofread <in.srt> <out.srt>   (run the binary inside the .app)
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
        guard let mode = arguments.first, ["--transcribe", "--resegment", "--proofread"].contains(mode) else {
            WhisperDropApp.main()
            return
        }

        // Keep the main thread free: parts of the pipeline (the spell checker) run on
        // the main actor, which a blocked main thread would never let in.
        Task.detached {
            do {
                try await DeveloperCommands.run(arguments)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        dispatchMain()
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

        if arguments[0] == "--proofread" {
            if let index = arguments.firstIndex(of: "--model"), index + 1 < arguments.count {
                guard let model = ProofreadingModelCatalog.model(id: arguments[index + 1]) else { throw UsageError() }
                TextImprovementModelLocator.override = model
            }
            let cues = try SubtitleImporter.load(input)
            let started = Date()
            let improved = try await TextImprovementService().improve(cues: cues) { _, _ in }
            try Data(SubtitleExporter.render(improved, format: .srt).utf8).write(to: output, options: .atomic)
            print(String(format: "proofread %d cues in %.1fs", improved.count, Date().timeIntervalSince(started)))
            return
        }

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
