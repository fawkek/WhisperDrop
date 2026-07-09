import Foundation

actor TextImprovementService {
    struct RuntimeUnavailableError: LocalizedError {
        var errorDescription: String? {
            AppText.pick(
                "Модель Qwen загружена, но локальный движок llama-cli не найден. Для релиза нужно встроить llama.cpp в приложение.",
                "The Qwen model is downloaded, but the local llama-cli runtime was not found. Bundle llama.cpp before release."
            )
        }
    }

    struct InvalidModelOutputError: LocalizedError {
        var errorDescription: String? {
            AppText.pick(
                "Модель вернула ответ в неподходящем формате.",
                "The model returned an unsupported response format."
            )
        }
    }

    func downloadModel(progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws {
        try await TextImprovementModelDownloader.download { downloadedBytes, totalBytes in
            progress(ModelDownloadProgress(downloadedBytes: downloadedBytes, totalBytes: totalBytes))
        }
    }

    func improve(
        cues: [SubtitleCue],
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [SubtitleCue] {
        guard TextImprovementModelLocator.isInstalled else {
            throw CocoaError(.fileNoSuchFile)
        }

        let runtime = try runtimeURL()
        var improved: [SubtitleCue] = []
        let chunks = cues.chunked(into: 12)
        for chunkIndex in chunks.indices {
            try Task.checkCancellation()
            let chunk = chunks[chunkIndex]
            for cue in chunk {
                for word in cue.text.split(whereSeparator: \.isWhitespace).prefix(12) {
                    progress(Double(chunkIndex) / Double(max(1, chunks.count)), String(word))
                }
            }

            let correctedTexts = try runModel(runtime: runtime, cues: chunk)
            guard correctedTexts.count == chunk.count else { throw InvalidModelOutputError() }
            improved.append(contentsOf: zip(chunk, correctedTexts).map { cue, text in
                SubtitleCue(start: cue.start, end: cue.end, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            })
            progress(Double(chunkIndex + 1) / Double(chunks.count), correctedTexts.last ?? "")
        }

        return improved
    }

    private func runtimeURL() throws -> URL {
        if let bundled = Bundle.main.resourceURL?
            .appending(path: "LLMRuntime", directoryHint: .isDirectory)
            .appending(path: "bin", directoryHint: .isDirectory)
            .appending(path: "llama-cli"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let installed = ModelLocator.modelsRoot
            .appending(path: "Runtime", directoryHint: .isDirectory)
            .appending(path: "bin", directoryHint: .isDirectory)
            .appending(path: "llama-cli")
        if FileManager.default.isExecutableFile(atPath: installed.path) {
            return installed
        }

        let candidates = [
            "/opt/homebrew/bin/llama-cli",
            "/usr/local/bin/llama-cli",
            "/opt/homebrew/bin/main",
            "/usr/local/bin/main"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }
        throw RuntimeUnavailableError()
    }

    private func runModel(runtime: URL, cues: [SubtitleCue]) throws -> [String] {
        let input = cues.map(\.text)
        let inputData = try JSONEncoder().encode(input)
        let inputJSON = String(decoding: inputData, as: UTF8.self)
        let prompt = """
        You are proofreading subtitles for deaf and hard-of-hearing viewers.
        Return ONLY a valid JSON array of strings. The array length and order must match the input.
        Fix only spelling, punctuation, capitalization, and spacing.
        Do not translate. Do not rewrite meaning. Do not add explanations.

        Input JSON:
        \(inputJSON)
        """

        let process = Process()
        process.executableURL = runtime
        process.arguments = [
            "-m", TextImprovementModelLocator.modelFile.path,
            "--no-display-prompt",
            "--temp", "0",
            "-ngl", "99",
            "-n", "2048",
            "-p", prompt
        ]
        if let libraryPath = runtimeLibraryPath(for: runtime) {
            var environment = ProcessInfo.processInfo.environment
            environment["DYLD_LIBRARY_PATH"] = libraryPath
            process.environment = environment
        }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let outputText = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let errorText = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(
                domain: "WhisperDrop.TextImprovement",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? outputText : errorText]
            )
        }

        guard let json = extractJSONArray(from: outputText),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            throw InvalidModelOutputError()
        }
        return decoded
    }

    private func runtimeLibraryPath(for runtime: URL) -> String? {
        let parent = runtime.deletingLastPathComponent().deletingLastPathComponent()
        let library = parent.appending(path: "lib", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: library.path) ? library.path : nil
    }

    private func extractJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start <= end else { return nil }
        return String(text[start...end])
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
