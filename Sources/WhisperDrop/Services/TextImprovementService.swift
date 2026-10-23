import Foundation
import OSLog

actor TextImprovementService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WhisperDrop",
        category: "Proofreading"
    )

    struct RuntimeUnavailableError: LocalizedError {
        var errorDescription: String? {
            AppText.pick(
                "Модель Qwen не установлена или повреждена.",
                "The Qwen model is missing or damaged."
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
        guard TextImprovementModelLocator.isInstalled else { throw RuntimeUnavailableError() }
        var improved: [SubtitleCue] = []
        var rejected = 0
        let chunkSize = 6
        let chunks = cues.chunked(into: chunkSize)
        Self.logger.info("BaseRT proofreading run started: cues=\(cues.count, privacy: .public), chunks=\(chunks.count, privacy: .public)")
        AppFileLog.write("BaseRT native Metal proofreading run started: cues=\(cues.count), chunks=\(chunks.count)")
        for chunkIndex in chunks.indices {
            try Task.checkCancellation()
            let chunk = chunks[chunkIndex]
            let firstWord = chunk.first?.text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            progress(Double(chunkIndex) / Double(chunks.count), firstWord)

            var correctedTexts: [String]
            do {
                AppFileLog.write("BaseRT Metal chunk \(chunkIndex + 1)/\(chunks.count) started")
                correctedTexts = try await runModel(texts: chunk.map(\.text))
                AppFileLog.write("BaseRT Metal chunk \(chunkIndex + 1) succeeded")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppFileLog.write("BaseRT Metal chunk \(chunkIndex + 1) failed, keeping original text: \(error.localizedDescription)")
                correctedTexts = chunk.map(\.text)
            }
            guard correctedTexts.count == chunk.count else { throw InvalidModelOutputError() }

            for (cue, candidate) in zip(chunk, correctedTexts) {
                let accepted = await MainActor.run {
                    ProofreadingGuard.accept(original: cue.text, corrected: candidate, isRealWord: SpellCheck.isRealWord)
                }
                if accepted != candidate.trimmingCharacters(in: .whitespacesAndNewlines) { rejected += 1 }
                improved.append(SubtitleCue(start: cue.start, end: cue.end, text: LineBreaker.rewrapIfNeeded(accepted)))
            }
            progress(Double(chunkIndex + 1) / Double(chunks.count), correctedTexts.last ?? "")
        }

        let cleaned = SubtitleHallucinationFilter.clean(improved)
        let removedCount = improved.count - cleaned.count
        AppFileLog.write("BaseRT native Metal proofreading run finished: removedHallucinations=\(removedCount), rejectedEdits=\(rejected)")
        return cleaned
    }

    /// Instructions go in the system message and `/no_think` closes the user message:
    /// with both, Qwen3 answers right away instead of spending the token budget on
    /// reasoning. Neighbouring cues are not passed as context: in tests the 0.6B model
    /// started rewriting them instead of the input.
    private static let systemPrompt = """
    You fix typos in Russian or English subtitle lines for deaf and hard-of-hearing viewers. \
    Fix only spelling, punctuation, capitalization and spacing. \
    Never change, add or remove words otherwise. Never translate. \
    Reply with OUTPUT_JSON: and a JSON array of strings, same length and order as the input, nothing else.
    """

    private func runModel(texts: [String]) async throws -> [String] {
        let inputJSON = String(decoding: try JSONEncoder().encode(texts), as: UTF8.self)
        let prompt = "Input JSON:\n\(inputJSON)\n/no_think"
        // Room for the corrected copy of the input plus the wrapper, never a fixed 512.
        let maxTokens = min(2_048, max(256, inputJSON.count / 2 + 96))

        let output = try await BaseRTProcess.run(
            executable: try baseRTRuntimeURL(),
            arguments: [
                TextImprovementModelLocator.modelFile.path,
                "--system", Self.systemPrompt,
                "--prompt", prompt,
                "--chat",
                "--max-tokens", String(maxTokens),
                "--temp", "0",
            ]
        )
        // The runtime echoes the prompt first; only what follows is the model's answer,
        // so the example array in the prompt can never be mistaken for it.
        let answer = output.range(of: prompt).map { String(output[$0.upperBound...]) } ?? output
        if let debugPath = ProcessInfo.processInfo.environment["WHISPERDROP_DEBUG_PROOFREAD"] {
            try? (prompt + "\n=====\n" + answer).write(toFile: debugPath, atomically: true, encoding: .utf8)
        }
        guard let decoded = Self.decodeModelOutput(answer, expectedCount: texts.count) else {
            throw InvalidModelOutputError()
        }
        return decoded
    }

    private func baseRTRuntimeURL() throws -> URL {
        guard let executable = Bundle.main.resourceURL?
            .appending(path: "BaseRTRuntime", directoryHint: .isDirectory)
            .appending(path: "basert-complete"),
            FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RuntimeUnavailableError()
        }
        return executable
    }

    static func decodeModelOutput(
        _ text: String,
        expectedCount: Int,
        excluding excluded: [String]? = nil
    ) -> [String]? {
        let candidates = jsonCandidates(from: text)
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let strings = try? JSONDecoder().decode([String].self, from: data),
               strings.count == expectedCount,
               strings != excluded {
                return strings
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["items", "output", "subtitles", "result", "results", "lines", "texts"] {
                    guard let values = object[key] as? [String], values.count == expectedCount,
                          values != excluded else { continue }
                    return values
                }
            }
        }
        return nil
    }

    private static func jsonCandidates(from text: String) -> [String] {
        var candidates: [String] = []
        var searchStart = text.startIndex
        while let marker = text.range(of: "OUTPUT_JSON:", range: searchStart..<text.endIndex) {
            let tail = String(text[marker.upperBound...])
            if let range = firstJSONRange(in: tail) {
                candidates.append(String(tail[range]))
            }
            searchStart = marker.upperBound
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
