import Foundation

/// A proofreading model in MLX format (a folder of config, tokenizer and weights).
struct ProofreadingModel: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let repository: String
    let files: [ModelFile]
    /// One short line shown under the name in the picker.
    let russianNote: String
    let englishNote: String

    var note: String { AppText.pick(russianNote, englishNote) }
    var size: Int64 { files.reduce(0) { $0 + $1.size } }
    var folderName: String { repository.split(separator: "/").last.map(String.init) ?? id }

    static func == (lhs: ProofreadingModel, rhs: ProofreadingModel) -> Bool { lhs.id == rhs.id }
}

private let qwenTokenizer = ModelFile(
    path: "tokenizer.json", size: 19_989_343,
    sha256: "87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4"
)

enum ProofreadingModelCatalog {
    static let models: [ProofreadingModel] = [
        ProofreadingModel(
            id: "qwen3.5-0.8b",
            displayName: "Qwen3.5 0.8B",
            repository: "mlx-community/Qwen3.5-0.8B-4bit",
            files: [
                .init(path: "chat_template.jinja", size: 7_755),
                .init(path: "config.json", size: 3_112),
                .init(path: "model.safetensors", size: 625_229_487, sha256: "f5a0d9dd3efa73510542a8023d610ff26be2b4b020d181cfc4bedaa1fcc5dd9e"),
                .init(path: "model.safetensors.index.json", size: 71_473),
                qwenTokenizer,
                .init(path: "tokenizer_config.json", size: 1_139),
            ],
            russianNote: "Самая компактная, экспериментальная",
            englishNote: "Smallest, experimental"
        ),
        ProofreadingModel(
            id: "qwen3.5-2b",
            displayName: "Qwen3.5 2B",
            repository: "mlx-community/Qwen3.5-2B-4bit",
            files: [
                .init(path: "chat_template.jinja", size: 7_755),
                .init(path: "config.json", size: 3_113),
                .init(path: "model.safetensors", size: 1_722_271_785, sha256: "713fe7e5d3c3965f7106b0d0ee17615f7869c23c8d327996df8c1196fbcf07d5"),
                .init(path: "model.safetensors.index.json", size: 81_722),
                qwenTokenizer,
                .init(path: "tokenizer_config.json", size: 1_139),
            ],
            russianNote: "Компактнее, ниже точность",
            englishNote: "Smaller, lower accuracy"
        ),
        ProofreadingModel(
            id: "qwen3.5-4b",
            displayName: "Qwen3.5 4B",
            repository: "mlx-community/Qwen3.5-4B-4bit",
            files: [
                .init(path: "chat_template.jinja", size: 7_756),
                .init(path: "config.json", size: 3_366),
                .init(path: "model.safetensors", size: 3_034_300_695, sha256: "5fb9acd0246866381cf8c5c354c6db1019f6498eec4ccb4f5edcc71ffeacb2db"),
                .init(path: "model.safetensors.index.json", size: 101_944),
                qwenTokenizer,
                .init(path: "tokenizer_config.json", size: 1_139),
            ],
            russianNote: "По умолчанию, лучший результат в тестах",
            englishNote: "Default, best result in our tests"
        ),
        ProofreadingModel(
            id: "gemma-4-e2b",
            displayName: "Gemma 4 E2B",
            repository: "mlx-community/gemma-4-e2b-it-4bit",
            files: [
                .init(path: "chat_template.jinja", size: 17_336),
                .init(path: "config.json", size: 6_395),
                .init(path: "generation_config.json", size: 208),
                .init(path: "model.safetensors", size: 3_550_670_554, sha256: "038e39a37a7667373d2c3991375446b10c96ae1d717a68674870343db376b76e"),
                .init(path: "model.safetensors.index.json", size: 218_323),
                .init(path: "tokenizer.json", size: 32_169_626, sha256: "cc8d3a0ce36466ccc1278bf987df5f71db1719b9ca6b4118264f45cb627bfe0f"),
                .init(path: "tokenizer_config.json", size: 2_740),
            ],
            russianNote: "Экспериментальная, крупная",
            englishNote: "Experimental, large"
        ),
    ]

    /// 4B performed best on both Russian and English subtitle fixtures.
    /// Keep the language entry point for future language-specific defaults.
    static func defaultModelID(forLanguage _: String) -> String {
        "qwen3.5-4b"
    }

    static func model(id: String) -> ProofreadingModel? { models.first { $0.id == id } }
}

enum TextImprovementModelLocator {
    private static let selectionKey = "ProofreadingModelID"
    /// Developer CLI only: use a model without changing the saved choice.
    nonisolated(unsafe) static var override: ProofreadingModel?

    /// The model the user picked, or the default for the system language.
    static var selected: ProofreadingModel {
        get {
            if let override { return override }
            if let id = UserDefaults.standard.string(forKey: selectionKey),
               let model = ProofreadingModelCatalog.model(id: id) {
                return model
            }
            let language = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return ProofreadingModelCatalog.model(id: ProofreadingModelCatalog.defaultModelID(forLanguage: language))
                ?? ProofreadingModelCatalog.models[0]
        }
        set { UserDefaults.standard.set(newValue.id, forKey: selectionKey) }
    }

    static var expectedDownloadBytes: Int64 { selected.size }
    static var displayName: String { selected.displayName }

    static var description: String {
        AppText.pick(
            "Локальная вычитка на Apple Silicon. Меняются только опечатки, пунктуация, регистр и пробелы.",
            "Local proofreading on Apple Silicon. Only typos, punctuation, capitalization and spacing change."
        )
    }

    static var modelsFolder: URL {
        ModelLocator.modelsRoot.appending(path: "Proofreading", directoryHint: .isDirectory)
    }

    static func folder(for model: ProofreadingModel) -> URL {
        modelsFolder.appending(path: model.folderName, directoryHint: .isDirectory)
    }

    static func isInstalled(_ model: ProofreadingModel, in directory: URL? = nil) -> Bool {
        let folder = directory ?? folder(for: model)
        return model.files.allSatisfy { ModelDownloader.fileSize(folder.appending(path: $0.path)) == $0.size }
    }

    static func downloadedBytes(_ model: ProofreadingModel, in directory: URL? = nil) -> Int64 {
        let folder = directory ?? folder(for: model)
        return model.files.reduce(0) { total, file in
            let url = folder.appending(path: file.path)
            if ModelDownloader.fileSize(url) == file.size { return total + file.size }
            return total + min(file.size, ModelDownloader.fileSize(url.appendingPathExtension("partial")))
        }
    }

    static var isInstalled: Bool { isInstalled(selected) }
    static var downloadedBytes: Int64 { downloadedBytes(selected) }

    /// Folders from the BaseRT, MLX and GGUF eras of proofreading, removed after a new download.
    static var legacyFolders: [URL] {
        ["TextImprovementBaseRT", "TextImprovementMLX", "TextImprovement"].map {
            ModelLocator.modelsRoot.appending(path: $0, directoryHint: .isDirectory)
        }
    }
}
