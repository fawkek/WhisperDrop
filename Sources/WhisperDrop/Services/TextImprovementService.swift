import Foundation

actor TextImprovementService {
    private enum InferenceMode {
        case metal
        case cpu
    }

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
            let previewWords = chunk.flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }
            let previewLimit = max(1, min(previewWords.count, 24))
            for wordIndex in 0..<previewLimit {
                try Task.checkCancellation()
                let chunkBase = Double(chunkIndex) / Double(max(1, chunks.count))
                let chunkSpan = 1.0 / Double(max(1, chunks.count))
                let visibleProgress = chunkBase + chunkSpan * 0.18 * Double(wordIndex + 1) / Double(previewLimit)
                progress(visibleProgress, previewWords[wordIndex])
                try await Task.sleep(for: .milliseconds(28))
            }

            let correctedTexts = (try? runModel(runtime: runtime, cues: chunk, mode: .metal))
                ?? (try? runModel(runtime: runtime, cues: chunk, mode: .cpu))
                ?? chunk.map(\.text)
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

    private func runModel(runtime: URL, cues: [SubtitleCue], mode: InferenceMode) throws -> [String] {
        let input = cues.map(\.text)
        let inputData = try JSONEncoder().encode(input)
        let inputJSON = String(decoding: inputData, as: UTF8.self)
        let prompt = """
        You are proofreading subtitles for deaf and hard-of-hearing viewers.
        Start your answer with OUTPUT_JSON: followed by a valid JSON array of strings.
        The array length and order must match the input.
        Fix only spelling, punctuation, capitalization, and spacing.
        Do not translate. Do not rewrite meaning. Do not add explanations.
        Example answer: OUTPUT_JSON:["Corrected first line.","Corrected second line."]

        Input JSON:
        \(inputJSON)
        """

        let process = Process()
        process.executableURL = runtime
        var arguments = [
            "-m", TextImprovementModelLocator.modelFile.path,
            "--no-display-prompt",
            "--single-turn",
            "--reasoning", "off",
            "--no-show-timings",
            "--color", "off",
            "--temp", "0",
            "-n", "512",
            "-p", prompt
        ]
        switch mode {
        case .metal:
            arguments.insert(contentsOf: ["-ngl", "99"], at: arguments.count - 2)
        case .cpu:
            arguments.insert(contentsOf: ["--device", "none", "--fit", "off", "--no-op-offload", "-ngl", "0"], at: arguments.count - 2)
        }
        process.arguments = arguments
        if let libraryPath = runtimeLibraryPath(for: runtime) {
            var environment = ProcessInfo.processInfo.environment
            environment["DYLD_LIBRARY_PATH"] = libraryPath
            process.environment = environment
        }

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let outputText = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "WhisperDrop.TextImprovement",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: outputText.isEmpty ? "llama-cli exited with code \(process.terminationStatus)" : outputText]
            )
        }

        guard let decoded = Self.decodeModelOutput(outputText, expectedCount: cues.count) else {
            throw InvalidModelOutputError()
        }
        return decoded
    }

    private func runtimeLibraryPath(for runtime: URL) -> String? {
        let parent = runtime.deletingLastPathComponent().deletingLastPathComponent()
        let library = parent.appending(path: "lib", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: library.path) ? library.path : nil
    }

    static func decodeModelOutput(_ text: String, expectedCount: Int) -> [String]? {
        let candidates = jsonCandidates(from: text)
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let strings = try? JSONDecoder().decode([String].self, from: data),
               strings.count == expectedCount {
                return strings
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["items", "output", "subtitles", "result", "results", "lines", "texts"] {
                    guard let values = object[key] as? [String], values.count == expectedCount else { continue }
                    return values
                }
            }
        }
        return nil
    }

    private static func jsonCandidates(from text: String) -> [String] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let marker = text.range(of: "OUTPUT_JSON:", range: searchStart..<text.endIndex) {
            let tail = text[marker.upperBound...]
            if let range = firstJSONRange(in: String(tail)) {
                ranges.append(marker.upperBound..<text.index(marker.upperBound, offsetBy: range.upperBound.utf16Offset(in: String(tail))))
            }
            searchStart = marker.upperBound
        }

        var candidates = ranges.compactMap { range in
            let tail = text[range]
            if let jsonRange = firstJSONRange(in: String(tail)) {
                return String(String(tail)[jsonRange])
            }
            return nil
        }

        candidates.append(contentsOf: fencedJSONBlocks(in: text))
        candidates.append(contentsOf: allJSONArrayCandidates(in: text))
        candidates.append(contentsOf: allJSONObjectCandidates(in: text))

        var unique: [String] = []
        for candidate in candidates.reversed() where !unique.contains(candidate) {
            unique.append(candidate)
        }
        return unique
    }

    private static func fencedJSONBlocks(in text: String) -> [String] {
        let pattern = #"```(?:json)?\s*([\s\S]*?)\s*```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            let block = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return firstJSONRange(in: block).map { String(block[$0]) }
        }
    }

    private static func allJSONArrayCandidates(in text: String) -> [String] {
        allJSONCandidates(in: text, opening: "[", closing: "]")
    }

    private static func allJSONObjectCandidates(in text: String) -> [String] {
        allJSONCandidates(in: text, opening: "{", closing: "}")
    }

    private static func firstJSONRange(in text: String) -> Range<String.Index>? {
        let arrayStart = text.firstIndex(of: "[")
        let objectStart = text.firstIndex(of: "{")
        let start: String.Index?
        let closing: Character
        switch (arrayStart, objectStart) {
        case let (.some(array), .some(object)) where array < object:
            start = array
            closing = "]"
        case (.some, .some), (.none, .some):
            start = objectStart
            closing = "}"
        case (.some, .none):
            start = arrayStart
            closing = "]"
        case (.none, .none):
            return nil
        }
        guard let start else { return nil }
        return balancedJSONRange(in: text, start: start, closing: closing)
    }

    private static func allJSONCandidates(in text: String, opening: Character, closing: Character) -> [String] {
        text.indices.compactMap { index in
            guard text[index] == opening,
                  let range = balancedJSONRange(in: text, start: index, closing: closing) else { return nil }
            return String(text[range])
        }
    }

    private static func balancedJSONRange(in text: String, start: String.Index, closing: Character) -> Range<String.Index>? {
        var depth = 0
        var isEscaped = false
        var isInsideString = false
        let opening: Character = closing == "]" ? "[" : "{"
        for index in text[start...].indices {
            let character = text[index]
            if isEscaped {
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                isInsideString.toggle()
                continue
            }
            guard !isInsideString else { continue }
            if character == opening { depth += 1 }
            if character == closing {
                depth -= 1
                if depth == 0 { return start..<text.index(after: index) }
            }
        }
        return nil
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
