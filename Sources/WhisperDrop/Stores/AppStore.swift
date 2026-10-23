import AppKit
import AVFoundation
import Foundation
import Observation
import OSLog
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppStore {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WhisperDrop",
        category: "Proofreading"
    )

    enum Phase: Equatable {
        case needsModel
        case ready
        case downloading
        case importingModel
        case preparing
        case selectingAudioTrack
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
    var proofreadingChangedCueCount: Int?
    private var shouldImproveAfterModelDownload = false
    var selectedFile: URL?
    var audioTracks: [AudioTrackOption] = []
    var selectedAudioTrackID: Int?
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

    init() {
        restoreDraftIfAvailable()
    }

    var isWorking: Bool {
        [.downloading, .importingModel, .preparing, .selectingAudioTrack, .transcribing, .downloadingImprovementModel, .improvingSubtitles].contains(phase)
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
        SubtitleDraftStore.clear()
        selectedFile = url
        audioTracks = []
        selectedAudioTrackID = nil
        cues = []
        proofreadingChangedCueCount = nil
        progress = 0
        let id = UUID()
        operationID = id
        phase = .preparing
        workTask = Task {
            do {
                let tracks = try await AudioExtractor.audioTracks(in: url)
                try Task.checkCancellation()
                guard operationID == id else { return }

                if tracks.count > 1 {
                    audioTracks = tracks
                    selectedAudioTrackID = tracks.first?.id
                    progress = 0
                    phase = .selectingAudioTrack
                } else {
                    try await transcribe(url, audioTrack: nil, operationID: id)
                }
            } catch is CancellationError {
                guard operationID == id else { return }
                phase = .ready
            } catch {
                guard operationID == id else { return }
                Self.logger.error("Transcription preparation failed: \(error.localizedDescription, privacy: .public)")
                AppFileLog.write("Transcription preparation failed: \(error.localizedDescription)")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func selectAudioTrack(_ id: Int) {
        guard phase == .selectingAudioTrack,
              audioTracks.contains(where: { $0.id == id }) else { return }
        selectedAudioTrackID = id
    }

    func continueWithSelectedAudioTrack() {
        guard phase == .selectingAudioTrack,
              let url = selectedFile,
              let selectedAudioTrackID,
              let track = audioTracks.first(where: { $0.id == selectedAudioTrackID }) else { return }

        let id = UUID()
        operationID = id
        progress = 0
        phase = .preparing
        workTask = Task {
            do {
                try await transcribe(url, audioTrack: track, operationID: id)
            } catch is CancellationError {
                guard operationID == id else { return }
                phase = .ready
            } catch {
                guard operationID == id else { return }
                Self.logger.error("Transcription preparation failed: \(error.localizedDescription, privacy: .public)")
                AppFileLog.write("Transcription preparation failed: \(error.localizedDescription)")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func transcribe(
        _ url: URL,
        audioTrack: AudioTrackOption?,
        operationID id: UUID
    ) async throws {
        let audio = try await AudioExtractor.prepare(url, audioTrack: audioTrack) { value in
            Task { @MainActor in
                guard self.operationID == id else { return }
                self.progress = value * 0.08
            }
        }
        defer {
            if audio != url { try? FileManager.default.removeItem(at: audio) }
        }

        try Task.checkCancellation()
        guard operationID == id else { throw CancellationError() }
        phase = .transcribing
        let result = try await service.transcribe(
            file: audio,
            progress: { value in
                Task { @MainActor in
                    guard self.operationID == id else { return }
                    self.progress = 0.08 + value * 0.92
                }
            }
        )
        try Task.checkCancellation()
        guard operationID == id else { throw CancellationError() }
        cues = result
        persistDraft()
        progress = 1
        phase = .finished
    }

    private func loadSubtitlesForImprovement(_ url: URL) {
        workTask?.cancel()
        selectedFile = url
        progress = 0
        improvementWord = ""
        proofreadingChangedCueCount = nil
        do {
            cues = try SubtitleImporter.load(url)
            exportFormat = SubtitleImporter.format(for: url)
            persistDraft()
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
        // A second click must not start a second writer on the same file.
        guard phase != .downloading else { return }
        workTask?.cancel()
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

    /// Lets the user pick a model they already have instead of downloading it.
    func importExistingModel() {
        guard !isWorking else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = AppText.pick("Выбрать", "Choose")
        panel.message = AppText.pick(
            "Выберите папку \(ModelLocator.modelName) или папку, в которой она лежит",
            "Choose the \(ModelLocator.modelName) folder or a folder that contains it"
        )
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let id = UUID()
        operationID = id
        modelDownloadError = nil
        progress = 0
        phase = .importingModel
        workTask = Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ModelImporter.importModel(from: folder) { value in
                        Task { @MainActor in
                            guard self.operationID == id else { return }
                            self.progress = value
                        }
                    }
                }.value
                guard operationID == id else { return }
                progress = 1
                phase = ModelLocator.isInstalled ? .ready : .needsModel
            } catch {
                guard operationID == id else { return }
                modelDownloadError = error.localizedDescription
                phase = .needsModel
            }
        }
    }

    func cancel() {
        let wasDownloading = phase == .downloading
        let wasSelectingAudioTrack = phase == .selectingAudioTrack
        let wasNeedsImprovementModel = phase == .needsImprovementModel
        let wasImprovementDownload = phase == .downloadingImprovementModel
        let wasImproving = phase == .improvingSubtitles
        operationID = UUID()
        workTask?.cancel()
        workTask = nil
        if wasDownloading {
            phase = .needsModel
        } else if wasSelectingAudioTrack {
            phase = .ready
        } else if wasNeedsImprovementModel || wasImprovementDownload {
            shouldImproveAfterModelDownload = false
            phase = .needsImprovementModel
        } else if wasImproving {
            shouldImproveAfterModelDownload = false
            phase = cues.isEmpty ? .ready : .finished
        } else {
            phase = ModelLocator.isInstalled ? .ready : .needsModel
        }
        progress = 0
        if wasDownloading { downloadedModelBytes = 0 }
        if wasImprovementDownload { improvementDownloadBytes = TextImprovementModelLocator.downloadedBytes }
        if wasImproving { improvementWord = "" }
        if wasSelectingAudioTrack {
            selectedFile = nil
            audioTracks = []
            selectedAudioTrackID = nil
        }
    }

    func improveSubtitles() {
        guard !cues.isEmpty else { return }
        persistDraft()
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
        proofreadingChangedCueCount = nil
        phase = .improvingSubtitles
        let originalCues = cues
        Self.logger.info("Proofreading started: cues=\(originalCues.count, privacy: .public)")
        AppFileLog.write("Proofreading started: cues=\(originalCues.count)")
        workTask = Task {
            do {
                let improved = try await improvementService.improve(
                    cues: originalCues,
                    progress: { value, word in
                        Task { @MainActor in
                            guard self.operationID == id else { return }
                            self.progress = value
                            self.improvementWord = word
                        }
                    }
                )
                guard operationID == id else { return }
                let changedCount = Self.changedCueCount(original: originalCues, improved: improved)
                cues = improved
                proofreadingChangedCueCount = changedCount
                persistDraft()
                progress = 1
                improvementWord = ""
                phase = .finished
                Self.logger.info("Proofreading finished: cues=\(improved.count, privacy: .public), changed=\(changedCount, privacy: .public)")
                AppFileLog.write("Proofreading finished: cues=\(improved.count), changed=\(changedCount)")
            } catch is CancellationError {
                guard operationID == id else { return }
                Self.logger.info("Proofreading cancelled")
                AppFileLog.write("Proofreading cancelled")
                phase = .finished
            } catch {
                guard operationID == id else { return }
                Self.logger.error("Proofreading failed: \(error.localizedDescription, privacy: .public)")
                AppFileLog.write("Proofreading failed: \(error.localizedDescription)")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func downloadImprovementModel() {
        guard phase != .downloadingImprovementModel else { return }
        workTask?.cancel()
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
        SubtitleDraftStore.clear()
        selectedFile = nil
        audioTracks = []
        selectedAudioTrackID = nil
        cues = []
        progress = 0
        improvementWord = ""
        proofreadingChangedCueCount = nil
        shouldImproveAfterModelDownload = false
        phase = .ready
    }

    func showLog() {
        ensureLogFileExists()
        NSWorkspace.shared.open(AppFileLog.logFile)
    }

    func showLogsFolder() {
        ensureLogFileExists()
        NSWorkspace.shared.activateFileViewerSelecting([AppFileLog.logFile])
    }

    private static func changedCueCount(original: [SubtitleCue], improved: [SubtitleCue]) -> Int {
        let improvedByTiming = Dictionary(
            improved.map { (CueTiming(start: $0.start, end: $0.end), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let originalTimings = Set(original.map { CueTiming(start: $0.start, end: $0.end) })
        let changedOriginals = original.reduce(0) { total, cue in
            let key = CueTiming(start: cue.start, end: cue.end)
            guard let improvedCue = improvedByTiming[key] else { return total + 1 }
            let originalText = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let improvedText = improvedCue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return total + (originalText == improvedText ? 0 : 1)
        }
        let addedCues = improved.reduce(0) { total, cue in
            total + (originalTimings.contains(CueTiming(start: cue.start, end: cue.end)) ? 0 : 1)
        }
        return changedOriginals + addedCues
    }

    private struct CueTiming: Hashable {
        let startMilliseconds: Int64
        let endMilliseconds: Int64

        init(start: TimeInterval, end: TimeInterval) {
            startMilliseconds = Int64((start * 1_000).rounded())
            endMilliseconds = Int64((end * 1_000).rounded())
        }
    }

    private func persistDraft() {
        guard !cues.isEmpty else { return }
        let draft = SubtitleDraft(
            sourcePath: selectedFile?.path,
            cues: cues,
            format: exportFormat,
            encoding: exportEncoding,
            changedCueCount: proofreadingChangedCueCount,
            updatedAt: Date()
        )
        do {
            try SubtitleDraftStore.save(draft)
        } catch {
            Self.logger.error("Could not save subtitle recovery draft: \(error.localizedDescription, privacy: .public)")
            AppFileLog.write("Could not save subtitle recovery draft: \(error.localizedDescription)")
        }
    }

    private func restoreDraftIfAvailable() {
        guard let draft = SubtitleDraftStore.load() else { return }
        selectedFile = draft.sourcePath.map { URL(fileURLWithPath: $0) }
        cues = draft.cues
        exportFormat = draft.format
        exportEncoding = draft.format.requiresUTF8 ? .utf8 : draft.encoding
        proofreadingChangedCueCount = draft.changedCueCount
        progress = 1
        phase = .finished
        AppFileLog.write("Recovered subtitle draft: cues=\(draft.cues.count)")
    }

    private func ensureLogFileExists() {
        if !FileManager.default.fileExists(atPath: AppFileLog.logFile.path) {
            AppFileLog.write("Log created")
        }
    }
}
