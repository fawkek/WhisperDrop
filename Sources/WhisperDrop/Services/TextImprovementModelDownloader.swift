import Foundation

enum TextImprovementModelDownloader {
    static func download(progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try FileManager.default.createDirectory(at: TextImprovementModelLocator.modelFolder, withIntermediateDirectories: true)
        if TextImprovementModelLocator.isInstalled {
            progress(TextImprovementModelLocator.expectedDownloadBytes, TextImprovementModelLocator.expectedDownloadBytes)
            return
        }
        let partial = TextImprovementModelLocator.partialFile
        if TextImprovementModelLocator.fileSize(partial) > TextImprovementModelLocator.expectedDownloadBytes {
            try truncate(partial, to: TextImprovementModelLocator.expectedDownloadBytes)
        }
        var retry = 0
        while TextImprovementModelLocator.fileSize(partial) < TextImprovementModelLocator.expectedDownloadBytes {
            try Task.checkCancellation()
            do {
                try await ResumableFileTransfer().download(
                    from: TextImprovementModelLocator.downloadURL,
                    to: partial,
                    expectedBytes: TextImprovementModelLocator.expectedDownloadBytes
                ) { received in
                    progress(received, TextImprovementModelLocator.expectedDownloadBytes)
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                retry += 1
                guard retry <= 5 else { throw error }
                try await Task.sleep(for: .seconds(min(16, 1 << (retry - 1))))
            }
        }
        if FileManager.default.fileExists(atPath: TextImprovementModelLocator.modelFile.path) {
            try FileManager.default.removeItem(at: TextImprovementModelLocator.modelFile)
        }
        try FileManager.default.moveItem(at: partial, to: TextImprovementModelLocator.modelFile)
        removeObsoleteModels()
        progress(TextImprovementModelLocator.expectedDownloadBytes, TextImprovementModelLocator.expectedDownloadBytes)
    }

    private static func removeObsoleteModels() {
        for folder in [TextImprovementModelLocator.legacyMLXFolder, TextImprovementModelLocator.legacyGGUFFolder] {
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            do {
                try FileManager.default.removeItem(at: folder)
                AppFileLog.write("Removed obsolete proofreading model folder: \(folder.lastPathComponent)")
            } catch {
                AppFileLog.write("Could not remove obsolete model folder: \(error.localizedDescription)")
            }
        }
    }

    private static func truncate(_ url: URL, to bytes: Int64) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.close()
        AppFileLog.write("Trimmed duplicate bytes from BaseRT model download")
    }
}
