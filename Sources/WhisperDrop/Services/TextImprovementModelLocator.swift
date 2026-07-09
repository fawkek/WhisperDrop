import Foundation

enum TextImprovementModelLocator {
    static let modelName = "Qwen3-0.6B-Q8_0.gguf"
    static let expectedDownloadBytes: Int64 = 639_446_688
    static let repository = "Qwen/Qwen3-0.6B-GGUF"

    static var displayName: String {
        "Qwen3 0.6B"
    }

    static var description: String {
        AppText.pick(
            "Небольшая мультиязычная модель для локальной вычитки субтитров.",
            "A small multilingual model for local subtitle proofreading."
        )
    }

    static var modelFolder: URL {
        ModelLocator.modelsRoot.appending(path: "TextImprovement", directoryHint: .isDirectory)
    }

    static var modelFile: URL {
        modelFolder.appending(path: modelName)
    }

    static var partialFile: URL {
        modelFile.appendingPathExtension("partial")
    }

    static var isInstalled: Bool {
        fileSize(modelFile) == expectedDownloadBytes
    }

    static var downloadedBytes: Int64 {
        if isInstalled { return expectedDownloadBytes }
        return min(expectedDownloadBytes, fileSize(partialFile))
    }

    static var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(modelName)?download=true")!
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { return 0 }
        return Int64(values?.fileSize ?? 0)
    }
}
