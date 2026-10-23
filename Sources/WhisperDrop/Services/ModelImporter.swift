import Foundation

/// Imports a Whisper Large v3 Core ML model the user already has (another Mac, a
/// MacWhisper or WhisperKit download) instead of downloading 1.6 GB again.
/// Every file is checked against the manifest by size, and large weights by SHA-256,
/// before anything is copied. The user's folder is never modified.
enum ModelImporter {
    struct ModelNotFoundError: LocalizedError {
        var errorDescription: String? {
            AppText.pick(
                "В этой папке нет модели \(ModelLocator.displayName). Выберите папку \(ModelLocator.modelName) или папку, в которой она лежит.",
                "This folder doesn't contain \(ModelLocator.displayName). Choose the \(ModelLocator.modelName) folder or a folder that contains it."
            )
        }
    }

    struct ModelMismatchError: LocalizedError {
        let path: String
        var errorDescription: String? {
            AppText.pick(
                "Файл \(path) не совпадает с оригиналом. Возможно, это другая версия модели или файл повреждён.",
                "\(path) doesn't match the original. It may be a different model version or a damaged file."
            )
        }
    }

    /// Finds the model inside `root` (the folder itself or a subfolder up to 4 levels deep).
    static func findModelFolder(
        in root: URL,
        manifest: [ModelFile] = ModelDownloader.files,
        maxDepth: Int = 4
    ) -> URL? {
        var queue: [(URL, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (folder, depth) = queue.removeFirst()
            if looksLikeModel(folder, manifest: manifest) { return folder }
            guard depth < maxDepth,
                  let children = try? FileManager.default.contentsOfDirectory(
                      at: folder,
                      includingPropertiesForKeys: [.isDirectoryKey],
                      options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else { continue }
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                // .mlmodelc folders are parts of a model, not containers of one.
                guard child.pathExtension != "mlmodelc" else { continue }
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    private static func looksLikeModel(_ folder: URL, manifest: [ModelFile]) -> Bool {
        manifest.allSatisfy { file in
            FileManager.default.fileExists(atPath: folder.appending(path: file.path).path)
        }
    }

    /// Checks and copies the model. `progress` runs from 0 to 1 over the bytes checked.
    static func importModel(
        from root: URL,
        to destination: URL = ModelLocator.modelFolder,
        manifest: [ModelFile] = ModelDownloader.files,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        guard let source = findModelFolder(in: root, manifest: manifest) else { throw ModelNotFoundError() }
        let total = Double(manifest.reduce(0) { $0 + $1.size })
        var checked: Int64 = 0

        for file in manifest {
            let url = source.appending(path: file.path)
            guard ModelDownloader.fileSize(url) == file.size else { throw ModelMismatchError(path: file.path) }
            if let hash = file.sha256, try ModelDownloader.sha256Prefix(of: url, byteCount: file.size) != hash {
                throw ModelMismatchError(path: file.path)
            }
            checked += file.size
            progress(Double(checked) / total * 0.9)
        }

        for file in manifest {
            let from = source.appending(path: file.path)
            let to = destination.appending(path: file.path)
            if from.standardizedFileURL == to.standardizedFileURL { continue }
            if ModelDownloader.fileSize(to) == file.size, file.sha256 == nil { continue }
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = to.appendingPathExtension("importing")
            try? FileManager.default.removeItem(at: temporary)
            // On the same APFS volume this is an instant clone, not a 1.6 GB copy.
            try FileManager.default.copyItem(at: from, to: temporary)
            if FileManager.default.fileExists(atPath: to.path) { try FileManager.default.removeItem(at: to) }
            try FileManager.default.moveItem(at: temporary, to: to)
            let partial = to.appendingPathExtension("partial")
            try? FileManager.default.removeItem(at: partial)
        }
        progress(1)
        AppFileLog.write("Imported existing model from \(source.path)")
    }
}
