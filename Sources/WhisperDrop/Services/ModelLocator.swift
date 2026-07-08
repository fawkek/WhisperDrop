import Foundation

enum ModelLocator {
    static let modelName = "openai_whisper-large-v3-v20240930"
    static let downloadVariant = "openai_whisper-large-v3-v20240930"
    static let expectedDownloadBytes: Int64 = 1_619_531_263
    static let downloadSource = "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/\(downloadVariant)"

    static var displayName: String {
        "OpenAI Whisper Large v3"
    }

    static var description: String {
        AppText.pick(
            "Лучший доступный вариант для точного распознавания речи. Работает локально.",
            "The best available option for accurate speech recognition. Runs locally."
        )
    }

    static var modelsRoot: URL {
        if let override = ProcessInfo.processInfo.environment["WHISPERDROP_MODELS_PATH"] {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appending(path: "WhisperDrop", directoryHint: .isDirectory)
            .appending(path: "Models", directoryHint: .isDirectory)
    }

    static var modelFolder: URL {
        modelsRoot.appending(path: modelName, directoryHint: .isDirectory)
    }

    static var tokenizerFolder: URL {
        if ProcessInfo.processInfo.environment["WHISPERDROP_MODELS_PATH"] != nil {
            return modelsRoot.appending(path: "tokenizer", directoryHint: .isDirectory)
        }
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appending(path: "Tokenizer", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: bundled.appending(path: "tokenizer.json").path) {
                return bundled
            }
        }
        return URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "Models/tokenizer", directoryHint: .isDirectory)
    }

    static var isInstalled: Bool {
        ModelDownloader.files.allSatisfy { file in
            let url = modelFolder.appending(path: file.path)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && Int64(values?.fileSize ?? 0) == file.size
        } && FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: "tokenizer.json").path)
    }

    static var downloadedVariantBytes: Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: modelsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator where url.pathComponents.contains(downloadVariant) {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return min(expectedDownloadBytes, total)
    }
}

struct ModelDownloadProgress: Sendable {
    let fraction: Double
    let downloadedBytes: Int64
    let totalBytes: Int64

    init(downloadedBytes: Int64, totalBytes: Int64) {
        self.totalBytes = totalBytes
        self.downloadedBytes = min(totalBytes, max(0, downloadedBytes))
        fraction = totalBytes > 0 ? Double(self.downloadedBytes) / Double(totalBytes) : 0
    }
}
