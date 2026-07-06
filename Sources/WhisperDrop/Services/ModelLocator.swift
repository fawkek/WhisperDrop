import Foundation

enum ModelLocator {
    static let modelName = "openai_whisper-large-v3-v20240930"

    static var modelsRoot: URL {
        if let override = ProcessInfo.processInfo.environment["WHISPERDROP_MODELS_PATH"] {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        if let resources = Bundle.main.resourceURL {
            return resources.appending(path: "Models", directoryHint: .isDirectory)
        }
        return URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "Models", directoryHint: .isDirectory)
    }

    static var modelFolder: URL {
        modelsRoot.appending(path: modelName, directoryHint: .isDirectory)
    }

    static var tokenizerFolder: URL {
        modelsRoot.appending(path: "tokenizer", directoryHint: .isDirectory)
    }

    static var isInstalled: Bool {
        let required = ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]
        return required.allSatisfy {
            FileManager.default.fileExists(atPath: modelFolder.appending(path: $0).path)
        } && FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: "tokenizer.json").path)
    }
}

