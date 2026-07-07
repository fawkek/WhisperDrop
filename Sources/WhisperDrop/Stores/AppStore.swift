import AppKit
import AVFoundation
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppStore {
    enum Phase: Equatable {
        case needsModel
        case ready
        case downloading
        case preparing
        case transcribing
        case finished
        case failed(String)
    }

    var phase: Phase = ModelLocator.isInstalled ? .ready : .needsModel
    var progress = 0.0
    var selectedFile: URL?
    var cues: [SubtitleCue] = []
    private let service = TranscriptionService()
    private var workTask: Task<Void, Never>?

    var isWorking: Bool {
        [.downloading, .preparing, .transcribing].contains(phase)
    }

    func accept(providers: [NSItemProvider]) -> Bool {
        guard !isWorking, let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = item as? URL }
            guard let url else { return }
            Task { @MainActor in self?.start(url) }
        }
        return true
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        start(url)
    }

    func start(_ url: URL) {
        guard ModelLocator.isInstalled else { phase = .needsModel; return }
        workTask?.cancel()
        selectedFile = url
        cues = []
        progress = 0
        phase = .preparing
        workTask = Task {
            do {
                let audio = try await AudioExtractor.prepare(url) { value in
                    Task { @MainActor in self.progress = value * 0.08 }
                }
                try Task.checkCancellation()
                phase = .transcribing
                let result = try await service.transcribe(
                    file: audio,
                    progress: { value in
                        Task { @MainActor in self.progress = 0.08 + value * 0.92 }
                    }
                )
                cues = result
                progress = 1
                phase = .finished
                if audio != url { try? FileManager.default.removeItem(at: audio) }
            } catch is CancellationError {
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func downloadModel() {
        phase = .downloading
        progress = 0
        workTask = Task {
            do {
                try await service.downloadModel { value in
                    Task { @MainActor in self.progress = value }
                }
                progress = 1
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        workTask?.cancel()
        phase = ModelLocator.isInstalled ? .ready : .needsModel
        progress = 0
    }

    func save() {
        guard !cues.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "srt")!]
        panel.nameFieldStringValue = (selectedFile?.deletingPathExtension().lastPathComponent ?? "subtitles") + ".srt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SRTFormatter.render(cues).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() {
        selectedFile = nil
        cues = []
        progress = 0
        phase = .ready
    }
}
