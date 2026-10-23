import AppKit
import Foundation

/// Runs the proofreading runtime as a child process. Output is drained while the
/// process runs, so a chatty model can't fill the pipe and hang, and cancelling the
/// task terminates the process instead of leaving it running in the background.
enum BaseRTProcess {
    struct Failure: LocalizedError {
        let status: Int32
        let message: String
        var errorDescription: String? {
            message.isEmpty ? "BaseRT exited with code \(status)." : message
        }
    }

    static func run(executable: URL, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // One reader per pipe, each reading to EOF: no pipe can fill up and block the
        // process, and bytes can't be reordered between competing readers.
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        let outputTask = Task.detached { outputHandle.readDataToEndOfFile() }
        let errorTask = Task.detached { errorHandle.readDataToEndOfFile() }

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    process.terminationHandler = { _ in continuation.resume() }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            } onCancel: {
                if process.isRunning { process.terminate() }
            }
        } catch {
            // The process never started: close our ends so the readers finish.
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            _ = await outputTask.value
            _ = await errorTask.value
            throw error
        }

        let output = String(decoding: await outputTask.value, as: UTF8.self)
        let errors = String(decoding: await errorTask.value, as: UTF8.self)
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw Failure(status: process.terminationStatus, message: errors.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}

/// Keeps the small proofreading model honest: a correction is accepted only when it is
/// the kind of change it was asked for. Viewers who rely on subtitles can't hear a word
/// the model swapped for another, so anything bigger keeps the original text.
///
/// A word may only change when the original is misspelled and the replacement is a real
/// word (checked by the system spell checker), and only by a few letters. A correctly
/// spelled word is never touched, so the model can't turn "короткий фильм" into
/// "короткие фильмы" or "рыбак" into "рыбки".
enum ProofreadingGuard {
    static func accept(
        original: String,
        corrected: String,
        isRealWord: (String) -> Bool
    ) -> String {
        let candidate = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return original }

        let before = words(original)
        let after = words(candidate)
        // Only punctuation, capitalisation or spacing changed.
        if before == after { return candidate }
        // Joining or splitting words is fine only when nothing but the spaces moved.
        guard before.count == after.count else {
            return before.joined() == after.joined() ? candidate : original
        }
        for (x, y) in zip(before, after) where x != y {
            guard !isRealWord(x), isRealWord(y) else { return original }
            // A swapped letter pair costs two edits; short words get one.
            let limit = x.count <= 3 ? 1 : max(2, Int((Double(x.count) * 0.4).rounded(.down)))
            if distance(Array(x), Array(y)) > limit { return original }
        }
        return candidate
    }

    /// Lower-cased words without punctuation; "ё" counts as "е".
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Levenshtein distance.
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

/// The system spell checker, used to tell typos from real words.
@MainActor
enum SpellCheck {
    static func isRealWord(_ word: String) -> Bool {
        guard word.count > 1, !word.allSatisfy(\.isNumber) else { return true }
        let language = word.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } ? "ru" : "en"
        let checker = NSSpellChecker.shared
        guard checker.availableLanguages.contains(language) else { return true }
        let range = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }
}
