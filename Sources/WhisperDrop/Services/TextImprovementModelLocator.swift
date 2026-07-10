import Foundation

enum TextImprovementModelLocator {
    static let modelName = "Qwen3-0.6B-Q4.base"
    static let expectedDownloadBytes: Int64 = 430_114_816
    static let repository = "basecompute/Qwen3-0.6B"

    static var displayName: String { "Qwen3 0.6B" }

    static var description: String {
        AppText.pick(
            "Небольшая мультиязычная модель для локальной вычитки субтитров. Использует нативный Metal на Apple Silicon.",
            "A small multilingual model for local subtitle proofreading. Uses native Metal on Apple Silicon."
        )
    }

    static var modelFolder: URL {
        ModelLocator.modelsRoot.appending(path: "TextImprovementBaseRT", directoryHint: .isDirectory)
    }

    static var modelFile: URL { modelFolder.appending(path: modelName) }
    static var partialFile: URL { modelFile.appendingPathExtension("partial") }

    static var legacyMLXFolder: URL {
        ModelLocator.modelsRoot.appending(path: "TextImprovementMLX", directoryHint: .isDirectory)
    }

    static var legacyGGUFFolder: URL {
        ModelLocator.modelsRoot.appending(path: "TextImprovement", directoryHint: .isDirectory)
    }

    static var isInstalled: Bool { fileSize(modelFile) == expectedDownloadBytes }

    static var downloadedBytes: Int64 {
        isInstalled ? expectedDownloadBytes : min(expectedDownloadBytes, fileSize(partialFile))
    }

    static var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(modelName)?download=true")!
    }

    static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { return 0 }
        return Int64(values?.fileSize ?? 0)
    }
}
