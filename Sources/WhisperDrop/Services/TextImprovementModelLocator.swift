import Foundation

struct TextImprovementModelFile: Sendable {
    let name: String
    let expectedBytes: Int64
}

enum TextImprovementModelLocator {
    static let repository = "mlx-community/Qwen3-0.6B-4bit"
    static let files: [TextImprovementModelFile] = [
        .init(name: "model.safetensors", expectedBytes: 335_450_584),
        .init(name: "tokenizer.json", expectedBytes: 11_422_654),
        .init(name: "vocab.json", expectedBytes: 2_776_833),
        .init(name: "merges.txt", expectedBytes: 1_671_853),
        .init(name: "model.safetensors.index.json", expectedBytes: 49_731),
        .init(name: "tokenizer_config.json", expectedBytes: 9_706),
        .init(name: "config.json", expectedBytes: 937),
        .init(name: "added_tokens.json", expectedBytes: 707),
        .init(name: "special_tokens_map.json", expectedBytes: 613)
    ]

    static let expectedDownloadBytes = files.reduce(Int64.zero) { $0 + $1.expectedBytes }

    static var displayName: String { "Qwen3 0.6B" }

    static var description: String {
        AppText.pick(
            "Небольшая мультиязычная модель для локальной вычитки субтитров. Использует Metal на Apple Silicon.",
            "A small multilingual model for local subtitle proofreading. Uses Metal on Apple Silicon."
        )
    }

    static var modelFolder: URL {
        ModelLocator.modelsRoot.appending(path: "TextImprovementMLX", directoryHint: .isDirectory)
    }

    static var legacyModelFile: URL {
        ModelLocator.modelsRoot
            .appending(path: "TextImprovement", directoryHint: .isDirectory)
            .appending(path: "Qwen3-0.6B-Q8_0.gguf")
    }

    static func fileURL(_ file: TextImprovementModelFile) -> URL {
        modelFolder.appending(path: file.name)
    }

    static func partialURL(_ file: TextImprovementModelFile) -> URL {
        fileURL(file).appendingPathExtension("partial")
    }

    static func downloadURL(_ file: TextImprovementModelFile) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(file.name)?download=true")!
    }

    static var isInstalled: Bool {
        files.allSatisfy { fileSize(fileURL($0)) == $0.expectedBytes }
    }

    static var downloadedBytes: Int64 {
        min(expectedDownloadBytes, files.reduce(Int64.zero) { total, file in
            let finalSize = fileSize(fileURL(file))
            return total + min(file.expectedBytes, max(finalSize, fileSize(partialURL(file))))
        })
    }

    static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { return 0 }
        return Int64(values?.fileSize ?? 0)
    }
}
