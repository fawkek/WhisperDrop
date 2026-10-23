import Foundation
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Runs proofreading models in-process with MLX (MIT-licensed, part of the app).
/// The model stays loaded for one proofreading run and is released afterwards, so
/// it doesn't hold gigabytes of memory while the app sits idle.
actor MLXProofreadingEngine {
    static let shared = MLXProofreadingEngine()

    private var container: ModelContainer?
    private var loadedFolder: URL?

    func respond(system: String, user: String, modelFolder: URL, maxTokens: Int) async throws -> String {
        let container = try await load(modelFolder)
        let session = ChatSession(
            container,
            instructions: system,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0),
            // Qwen3 and Qwen3.5 otherwise "think" before answering and spend the budget.
            additionalContext: ["enable_thinking": false]
        )
        return try await session.respond(to: user)
    }

    func unload() {
        container = nil
        loadedFolder = nil
    }

    private func load(_ folder: URL) async throws -> ModelContainer {
        if let container, loadedFolder == folder { return container }
        container = nil
        let loaded = try await loadModelContainer(from: folder, using: SwiftTransformersTokenizerLoader())
        container = loaded
        loadedFolder = folder
        return loaded
    }
}

/// Adapts swift-transformers tokenizers to mlx-swift-lm (same bridge as its
/// `#huggingFaceTokenizerLoader` macro, without the Hugging Face downloader).
private struct SwiftTransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
