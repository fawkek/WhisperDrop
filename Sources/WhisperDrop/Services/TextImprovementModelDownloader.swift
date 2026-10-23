import Foundation

/// Downloads an MLX proofreading model file by file, resumable, with the same
/// integrity rules as the speech model: exact sizes, SHA-256 for the large files.
enum TextImprovementModelDownloader {
    static func download(
        _ model: ProofreadingModel = TextImprovementModelLocator.selected,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let folder = TextImprovementModelLocator.folder(for: model)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let total = model.size
        progress(TextImprovementModelLocator.downloadedBytes(model), total)

        for file in model.files {
            try Task.checkCancellation()
            let destination = folder.appending(path: file.path)
            if ModelDownloader.fileSize(destination) == file.size { continue }
            let before = TextImprovementModelLocator.downloadedBytes(model) - min(file.size, ModelDownloader.fileSize(destination.appendingPathExtension("partial")))
            let partial = destination.appendingPathExtension("partial")
            let url = URL(string: "https://huggingface.co/\(model.repository)/resolve/main/\(file.path)?download=true")!
            var retry = 0
            var hashFailures = 0
            while true {
                if ModelDownloader.fileSize(partial) > file.size { try ModelDownloader.truncate(partial, to: file.size) }
                while ModelDownloader.fileSize(partial) < file.size {
                    try Task.checkCancellation()
                    do {
                        try await ResumableFileTransfer().download(from: url, to: partial, expectedBytes: file.size) { received in
                            progress(before + received, total)
                        }
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        retry += 1
                        guard retry <= 5 else { throw error }
                        try await Task.sleep(for: .seconds(min(16, 1 << (retry - 1))))
                    }
                }
                guard let expected = file.sha256 else { break }
                if try ModelDownloader.sha256Prefix(of: partial, byteCount: file.size) == expected { break }
                AppFileLog.write("Proofreading model file failed SHA-256 check, downloading again: \(file.path)")
                try FileManager.default.removeItem(at: partial)
                hashFailures += 1
                guard hashFailures <= 1 else { throw ModelDownloader.ModelIntegrityError(path: file.path) }
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partial, to: destination)
        }
        removeLegacyModels()
        progress(total, total)
    }

    /// Earlier proofreading engines kept their models elsewhere; they are dead weight now.
    private static func removeLegacyModels() {
        for folder in TextImprovementModelLocator.legacyFolders where FileManager.default.fileExists(atPath: folder.path) {
            do {
                try FileManager.default.removeItem(at: folder)
                AppFileLog.write("Removed obsolete proofreading model folder: \(folder.lastPathComponent)")
            } catch {
                AppFileLog.write("Could not remove obsolete model folder: \(error.localizedDescription)")
            }
        }
    }
}
