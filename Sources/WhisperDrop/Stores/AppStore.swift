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
        case needsImprovementModel
        case downloadingImprovementModel
        case improvingSubtitles
        case failed(String)
    }

    var phase: Phase = ModelLocator.isInstalled ? .ready : .needsModel
    var progress = 0.0
    var downloadedModelBytes: Int64 = 0
    var modelDownloadTotalBytes: Int64 = ModelLocator.expectedDownloadBytes
    var modelDownloadError: String?
    var improvementDownloadBytes: Int64 = TextImprovementModelLocator.downloadedBytes
    var improvementDownloadTotalBytes: Int64 = TextImprovementModelLocator.expectedDownloadBytes
    var improvementDownloadError: String?
    var improvementWord: String = ""
    private var shouldImproveAfterModelDownload = false
    var selectedFile: URL?
    var cues: [SubtitleCue] = []
    var exportFormat: SubtitleFormat = .srt {
        didSet {
            if exportFormat.requiresUTF8 { exportEncoding = .utf8 }
        }
    }
    var exportEncoding: SubtitleEncoding = .utf8
    private let service = TranscriptionService()
    private let improvementService = TextImprovementService()
    private var workTask: Task<Void, Never>?
    private var operationID = UUID()

    var isWorking: Bool {
        [.downloading, .preparing, .transcribing, .downloadingImprovementModel, .improvingSubtitles].contains(phase)
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
        panel.allowedContentTypes = [
            .movie,
            .audio,
            .mpeg4Movie,
            .quickTimeMovie,
            .plainText,
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "vtt") ?? .plainText,
            UTType(filenameExtension: "ass") ?? .plainText
        ]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        start(url)
    }

    func start(_ url: URL) {
        if SubtitleImporter.isSubtitleFile(url) {
            loadSubtitlesForImprovement(url)
            return
        }
        guard ModelLocator.isInstalled else { phase = .needsModel; return }
        workTask?.cancel()
        shouldImproveAfterModelDownload = false
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

    private func loadSubtitlesForImprovement(_ url: URL) {
        workTask?.cancel()
        selectedFile = url
        progress = 0
        improvementWord = ""
        do {
            cues = try SubtitleImporter.load(url)
            exportFormat = SubtitleImporter.format(for: url)
            if TextImprovementModelLocator.isInstalled {
                shouldImproveAfterModelDownload = false
                improveSubtitles()
            } else {
                shouldImproveAfterModelDownload = true
                improvementDownloadError = nil
                improvementDownloadBytes = TextImprovementModelLocator.downloadedBytes
                improvementDownloadTotalBytes = TextImprovementModelLocator.expectedDownloadBytes
                phase = .needsImprovementModel
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func downloadModel() {
        let id = UUID()
        operationID = id
        modelDownloadError = nil
        phase = .downloading
        downloadedModelBytes = ModelLocator.downloadedVariantBytes
        modelDownloadTotalBytes = ModelLocator.expectedDownloadBytes
        progress = min(1, Double(downloadedModelBytes) / Double(modelDownloadTotalBytes))
        workTask = Task {
            do {
                try await service.downloadModel { value in
                    Task { @MainActor in
                        guard self.operationID == id else { return }
                        self.modelDownloadTotalBytes = value.totalBytes
                        self.downloadedModelBytes = value.downloadedBytes
                        self.progress = value.fraction
                    }
                }
                try Task.checkCancellation()
                guard operationID == id else { return }
                progress = 1
                downloadedModelBytes = modelDownloadTotalBytes
                phase = .ready
            } catch is CancellationError {
                guard operationID == id else { return }
                phase = .needsModel
            } catch {
                guard operationID == id else { return }
                modelDownloadError = error.localizedDescription
                phase = .needsModel
            }
        }
    }

    func cancel() {
        let wasDownloading = phase == .downloading
        let wasNeedsImprovementModel = phase == .needsImprovementModel
        let wasImprovementDownload = phase == .downloadingImprovementModel
        let wasImproving = phase == .improvingSubtitles
        operationID = UUID()
        workTask?.cancel()
        workTask = nil
        if wasDownloading {
            phase = .needsModel
        } else if wasNeedsImprovementModel || wasImprovementDownload || wasImproving {
            shouldImproveAfterModelDownload = false
            phase = cues.isEmpty ? .ready : .finished
        } else {
            phase = ModelLocator.isInstalled ? .ready : .needsModel
        }
        progress = 0
        if wasDownloading { downloadedModelBytes = 0 }
        if wasImprovementDownload { improvementDownloadBytes = TextImprovementModelLocator.downloadedBytes }
        if wasImproving { improvementWord = "" }
    }

    func improveSubtitles() {
        guard !cues.isEmpty else { return }
        shouldImproveAfterModelDownload = false
        guard TextImprovementModelLocator.isInstalled else {
            improvementDownloadError = nil
            improvementDownloadBytes = TextImprovementModelLocator.downloadedBytes
            improvementDownloadTotalBytes = TextImprovementModelLocator.expectedDownloadBytes
            progress = min(1, Double(improvementDownloadBytes) / Double(improvementDownloadTotalBytes))
            phase = .needsImprovementModel
            return
        }

        let id = UUID()
        operationID = id
        progress = 0
        improvementWord = ""
        phase = .improvingSubtitles
        workTask = Task {
            do {
                let improved = try await improvementService.improve(
                    cues: cues,
                    progress: { value, word in
                        Task { @MainActor in
                            guard self.operationID == id else { return }
                            self.progress = value
                            self.improvementWord = word
                        }
                    }
                )
                guard operationID == id else { return }
                cues = improved
                progress = 1
                improvementWord = ""
                phase = .finished
            } catch is CancellationError {
                guard operationID == id else { return }
                phase = .finished
            } catch {
                guard operationID == id else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func downloadImprovementModel() {
        let id = UUID()
        operationID = id
        improvementDownloadError = nil
        phase = .downloadingImprovementModel
        improvementDownloadBytes = TextImprovementModelLocator.downloadedBytes
        improvementDownloadTotalBytes = TextImprovementModelLocator.expectedDownloadBytes
        progress = min(1, Double(improvementDownloadBytes) / Double(improvementDownloadTotalBytes))
        workTask = Task {
            do {
                try await improvementService.downloadModel { value in
                    Task { @MainActor in
                        guard self.operationID == id else { return }
                        self.improvementDownloadTotalBytes = value.totalBytes
                        self.improvementDownloadBytes = value.downloadedBytes
                        self.progress = value.fraction
                    }
                }
                try Task.checkCancellation()
                guard operationID == id else { return }
                progress = 1
                improvementDownloadBytes = improvementDownloadTotalBytes
                if shouldImproveAfterModelDownload {
                    shouldImproveAfterModelDownload = false
                    improveSubtitles()
                } else {
                    phase = .finished
                }
            } catch is CancellationError {
                guard operationID == id else { return }
                phase = .needsImprovementModel
            } catch {
                guard operationID == id else { return }
                improvementDownloadError = error.localizedDescription
                phase = .needsImprovementModel
            }
        }
    }

    func save() {
        guard !cues.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: exportFormat.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = (selectedFile?.deletingPathExtension().lastPathComponent ?? "subtitles") + "." + exportFormat.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = SubtitleExporter.render(cues, format: exportFormat)
            let data = try SubtitleExporter.data(text, encoding: exportEncoding)
            try data.write(to: url, options: .atomic)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() {
        selectedFile = nil
        cues = []
        progress = 0
        improvementWord = ""
        shouldImproveAfterModelDownload = false
        phase = .ready
    }
}
