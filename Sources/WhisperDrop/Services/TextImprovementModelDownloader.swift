import Foundation

enum TextImprovementModelDownloader {
    static func download(progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try FileManager.default.createDirectory(
            at: TextImprovementModelLocator.modelFolder,
            withIntermediateDirectories: true
        )

        for file in TextImprovementModelLocator.files {
            try Task.checkCancellation()
            let final = TextImprovementModelLocator.fileURL(file)
            let partial = TextImprovementModelLocator.partialURL(file)
            if TextImprovementModelLocator.fileSize(final) == file.expectedBytes {
                progress(TextImprovementModelLocator.downloadedBytes, TextImprovementModelLocator.expectedDownloadBytes)
                continue
            }
            if TextImprovementModelLocator.fileSize(partial) > file.expectedBytes {
                try FileManager.default.removeItem(at: partial)
            }

            var retry = 0
            while TextImprovementModelLocator.fileSize(partial) < file.expectedBytes {
                try Task.checkCancellation()
                do {
                    let completedBeforeFile = completedBytes(before: file)
                    let transfer = ResumableFileTransfer()
                    try await transfer.download(
                        from: TextImprovementModelLocator.downloadURL(file),
                        to: partial,
                        expectedBytes: file.expectedBytes
                    ) { receivedBytes in
                        progress(
                            min(TextImprovementModelLocator.expectedDownloadBytes, completedBeforeFile + receivedBytes),
                            TextImprovementModelLocator.expectedDownloadBytes
                        )
                    }
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    retry += 1
                    guard retry <= 5 else { throw error }
                    try await Task.sleep(for: .seconds(min(16, 1 << (retry - 1))))
                }
            }

            if FileManager.default.fileExists(atPath: final.path) {
                try FileManager.default.removeItem(at: final)
            }
            try FileManager.default.moveItem(at: partial, to: final)
            progress(TextImprovementModelLocator.downloadedBytes, TextImprovementModelLocator.expectedDownloadBytes)
        }

        guard TextImprovementModelLocator.isInstalled else { throw CocoaError(.fileReadCorruptFile) }
        removeLegacyGGUF()
        progress(TextImprovementModelLocator.expectedDownloadBytes, TextImprovementModelLocator.expectedDownloadBytes)
    }

    private static func completedBytes(before target: TextImprovementModelFile) -> Int64 {
        var total: Int64 = 0
        for file in TextImprovementModelLocator.files {
            if file.name == target.name { break }
            total += file.expectedBytes
        }
        return total
    }

    private static func removeLegacyGGUF() {
        let legacy = TextImprovementModelLocator.legacyModelFile
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        do {
            try FileManager.default.removeItem(at: legacy)
            AppFileLog.write("Removed obsolete GGUF proofreading model after MLX installation")
        } catch {
            AppFileLog.write("Could not remove obsolete GGUF model: \(error.localizedDescription)")
        }
    }
}
