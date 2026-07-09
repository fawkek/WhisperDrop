import Foundation

enum TextImprovementModelDownloader {
    static func download(progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try FileManager.default.createDirectory(
            at: TextImprovementModelLocator.modelFolder,
            withIntermediateDirectories: true
        )

        if fileSize(TextImprovementModelLocator.modelFile) == TextImprovementModelLocator.expectedDownloadBytes {
            progress(TextImprovementModelLocator.expectedDownloadBytes, TextImprovementModelLocator.expectedDownloadBytes)
            return
        }

        let partial = TextImprovementModelLocator.partialFile
        if fileSize(partial) > TextImprovementModelLocator.expectedDownloadBytes {
            try FileManager.default.removeItem(at: partial)
        }

        var retry = 0
        while fileSize(partial) < TextImprovementModelLocator.expectedDownloadBytes {
            try Task.checkCancellation()
            do {
                let transfer = ResumableFileTransfer()
                try await transfer.download(
                    from: TextImprovementModelLocator.downloadURL,
                    to: partial,
                    expectedBytes: TextImprovementModelLocator.expectedDownloadBytes
                ) { receivedBytes in
                    progress(receivedBytes, TextImprovementModelLocator.expectedDownloadBytes)
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                retry += 1
                guard retry <= 5 else { throw error }
                let delay = min(16, 1 << (retry - 1))
                try await Task.sleep(for: .seconds(delay))
            }
        }

        if FileManager.default.fileExists(atPath: TextImprovementModelLocator.modelFile.path) {
            try FileManager.default.removeItem(at: TextImprovementModelLocator.modelFile)
        }
        try FileManager.default.moveItem(at: partial, to: TextImprovementModelLocator.modelFile)
        progress(TextImprovementModelLocator.expectedDownloadBytes, TextImprovementModelLocator.expectedDownloadBytes)
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { return 0 }
        return Int64(values?.fileSize ?? 0)
    }
}
