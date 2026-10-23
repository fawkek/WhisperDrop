import CryptoKit
import Foundation

struct ModelFile: Sendable {
    let path: String
    let size: Int64
    let sha256: String?

    init(path: String, size: Int64, sha256: String? = nil) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }
}

enum ModelDownloader {
    static let files: [ModelFile] = [
        .init(path: "AudioEncoder.mlmodelc/analytics/coremldata.bin", size: 243),
        .init(path: "AudioEncoder.mlmodelc/coremldata.bin", size: 348),
        .init(path: "AudioEncoder.mlmodelc/metadata.json", size: 1_772),
        .init(path: "AudioEncoder.mlmodelc/model.mil", size: 527_644),
        .init(path: "AudioEncoder.mlmodelc/model.mlmodel", size: 441_653),
        .init(path: "AudioEncoder.mlmodelc/weights/weight.bin", size: 1_273_974_400, sha256: "98daf651a919978e28fe185daf55ce2f70085a8e59fa07fe8a4d08c87d368ae4"),
        .init(path: "MelSpectrogram.mlmodelc/analytics/coremldata.bin", size: 243),
        .init(path: "MelSpectrogram.mlmodelc/coremldata.bin", size: 329),
        .init(path: "MelSpectrogram.mlmodelc/metadata.json", size: 1_878),
        .init(path: "MelSpectrogram.mlmodelc/model.mil", size: 10_166),
        .init(path: "MelSpectrogram.mlmodelc/model.mlmodel", size: 8_962),
        .init(path: "MelSpectrogram.mlmodelc/weights/weight.bin", size: 373_376, sha256: "81275398516781f9755514a5ab85db4687374dd611013625f3d4493588783968"),
        .init(path: "TextDecoder.mlmodelc/analytics/coremldata.bin", size: 243),
        .init(path: "TextDecoder.mlmodelc/coremldata.bin", size: 633),
        .init(path: "TextDecoder.mlmodelc/metadata.json", size: 4_756),
        .init(path: "TextDecoder.mlmodelc/model.mil", size: 132_679),
        .init(path: "TextDecoder.mlmodelc/model.mlmodel", size: 113_164),
        .init(path: "TextDecoder.mlmodelc/weights/weight.bin", size: 343_933_748, sha256: "47b2703aa37448e09cf2f06e45984fabd5ded4c34ba3400cec38a5294af39dc1"),
        .init(path: "config.json", size: 1_255),
        .init(path: "generation_config.json", size: 3_771),
    ]

    static var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    static var downloadedBytes: Int64 { installedBytes() }

    static func download(progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try FileManager.default.createDirectory(at: ModelLocator.modelFolder, withIntermediateDirectories: true)
        try repairValidOversizedFiles()
        try migrateLegacyDownloads()

        var completedBytes = installedBytes()
        progress(completedBytes, totalBytes)

        for file in files {
            try Task.checkCancellation()
            let destination = ModelLocator.modelFolder.appending(path: file.path)
            if fileSize(destination) == file.size { continue }

            let partial = destination.appendingPathExtension("partial")
            let legacyIncoming = partial.appendingPathExtension("incoming")
            if FileManager.default.fileExists(atPath: legacyIncoming.path) {
                try FileManager.default.removeItem(at: legacyIncoming)
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let resumedBytes = min(file.size, fileSize(partial))
            let bytesBeforeFile = completedBytes - resumedBytes
            let remoteURL = try remoteURL(for: file.path)
            var retry = 0
            var hashFailures = 0
            while true {
                while fileSize(partial) < file.size {
                    try Task.checkCancellation()
                    do {
                        let transfer = ResumableFileTransfer()
                        try await transfer.download(
                            from: remoteURL,
                            to: partial,
                            expectedBytes: file.size
                        ) { received in
                            progress(bytesBeforeFile + received, totalBytes)
                        }
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        retry += 1
                        guard retry <= 5 else { throw error }
                        let delay = min(16, 1 << (retry - 1))
                        try await Task.sleep(for: .seconds(delay))
                    }
                }
                try Task.checkCancellation()
                // Extra bytes past the end never belong to the file.
                if fileSize(partial) > file.size { try truncate(partial, to: file.size) }
                guard let expectedHash = file.sha256 else { break }
                if try sha256Prefix(of: partial, byteCount: file.size) == expectedHash { break }
                // Corrupted download: start this file over, once.
                AppFileLog.write("Model file failed SHA-256 check, downloading again: \(file.path)")
                try FileManager.default.removeItem(at: partial)
                hashFailures += 1
                guard hashFailures <= 1 else { throw ModelIntegrityError(path: file.path) }
                progress(bytesBeforeFile, totalBytes)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partial, to: destination)
            completedBytes = bytesBeforeFile + file.size
            progress(completedBytes, totalBytes)
        }
    }

    private static func remoteURL(for relativePath: String) throws -> URL {
        guard var components = URLComponents(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main") else {
            throw URLError(.badURL)
        }
        components.path += "/\(ModelLocator.downloadVariant)/\(relativePath)"
        components.queryItems = [URLQueryItem(name: "download", value: "true")]
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private static func installedBytes() -> Int64 {
        files.reduce(0) { total, file in
            let destination = ModelLocator.modelFolder.appending(path: file.path)
            if fileSize(destination) == file.size { return total + file.size }
            let partial = destination.appendingPathExtension("partial")
            return total + min(file.size, fileSize(partial))
        }
    }

    /// Recovers files that were downloaded completely but had extra bytes appended
    /// afterwards: when the first `size` bytes match the expected SHA-256, the tail is cut
    /// off instead of downloading the whole file again. Checks finished files and
    /// `.partial` files alike.
    static func repairValidOversizedFiles(
        in folder: URL = ModelLocator.modelFolder,
        manifest: [ModelFile] = files
    ) throws {
        for file in manifest {
            guard let expectedHash = file.sha256 else { continue }
            let destination = folder.appending(path: file.path)
            let partial = destination.appendingPathExtension("partial")

            if fileSize(destination) > file.size,
               try sha256Prefix(of: destination, byteCount: file.size) == expectedHash {
                try truncate(destination, to: file.size)
                AppFileLog.write("Repaired oversized model file: \(file.path)")
            }
            if fileSize(destination) == file.size {
                if FileManager.default.fileExists(atPath: partial.path) {
                    try FileManager.default.removeItem(at: partial)
                }
                continue
            }
            guard fileSize(partial) >= file.size,
                  try sha256Prefix(of: partial, byteCount: file.size) == expectedHash else { continue }
            try truncate(partial, to: file.size)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partial, to: destination)
            AppFileLog.write("Recovered complete model file from partial download: \(file.path)")
        }
    }

    static func truncate(_ url: URL, to size: Int64) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(size))
    }

    struct ModelIntegrityError: LocalizedError {
        let path: String
        var errorDescription: String? {
            AppText.pick(
                "Файл модели скачался повреждённым дважды подряд (\(path)). Проверьте соединение и попробуйте снова.",
                "A model file was corrupted twice in a row (\(path)). Check your connection and try again."
            )
        }
    }

    static func sha256Prefix(of url: URL, byteCount: Int64) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = byteCount
        while remaining > 0 {
            let count = Int(min(1_048_576, remaining))
            guard let data = try handle.read(upToCount: count), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= Int64(data.count)
        }
        guard remaining == 0 else { throw CocoaError(.fileReadCorruptFile) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func migrateLegacyDownloads() throws {
        let legacyRoot = ModelLocator.modelsRoot
            .appending(path: "models/argmaxinc/whisperkit-coreml", directoryHint: .isDirectory)
        let legacyModel = legacyRoot.appending(path: ModelLocator.downloadVariant, directoryHint: .isDirectory)
        let legacyCache = legacyRoot
            .appending(path: ".cache/huggingface/download", directoryHint: .isDirectory)
            .appending(path: ModelLocator.downloadVariant, directoryHint: .isDirectory)

        for file in files {
            let destination = ModelLocator.modelFolder.appending(path: file.path)
            if fileSize(destination) == file.size { continue }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let legacyComplete = legacyModel.appending(path: file.path)
            if fileSize(legacyComplete) == file.size {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: legacyComplete, to: destination)
                continue
            }

            let partial = destination.appendingPathExtension("partial")
            guard !FileManager.default.fileExists(atPath: partial.path) else { continue }
            let cacheDirectory = legacyCache
                .appending(path: file.path)
                .deletingLastPathComponent()
            let prefix = URL(filePath: file.path).lastPathComponent + "."
            guard let candidates = try? FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            ), let incomplete = candidates.first(where: {
                $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "incomplete"
            }) else { continue }
            try FileManager.default.moveItem(at: incomplete, to: partial)
        }
    }

    /// Size read straight from the file system. `URL.resourceValues` can return a cached
    /// value for a file that is still being written.
    static func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}

final class ResumableFileTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct ResumeRejectedError: LocalizedError {
        var errorDescription: String? {
            AppText.pick(
                "Сервер временно не подтвердил продолжение загрузки.",
                "The server temporarily rejected download resumption."
            )
        }
    }

    private struct HTTPError: LocalizedError {
        let statusCode: Int
        let host: String

        var errorDescription: String? {
            AppText.pick(
                "Сервер загрузки вернул ошибку HTTP \(statusCode) — \(host).",
                "The download server returned HTTP \(statusCode) — \(host)."
            )
        }
    }

    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var continuation: CheckedContinuation<Void, Error>?
    private var progress: (@Sendable (Int64) -> Void)?
    private var expectedBytes: Int64 = 0
    private var receivedBytes: Int64 = 0
    private var initialBytes: Int64 = 0
    private var rangeHeader: String?
    private var finished = false

    func download(
        from url: URL,
        to partialURL: URL,
        expectedBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        self.expectedBytes = expectedBytes
        self.progress = progress
        receivedBytes = Self.fileSize(partialURL)
        if receivedBytes > expectedBytes {
            let handle = try FileHandle(forWritingTo: partialURL)
            try handle.truncate(atOffset: UInt64(expectedBytes))
            try handle.close()
            receivedBytes = expectedBytes
        }
        if !FileManager.default.fileExists(atPath: partialURL.path) {
            _ = FileManager.default.createFile(atPath: partialURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partialURL)
        fileHandle = handle
        // Resume from where the file really ends, never from a cached size: a stale
        // size requests bytes the file already has and appends them a second time.
        receivedBytes = Int64(try handle.seekToEnd())
        initialBytes = receivedBytes
        progress(receivedBytes)
        if initialBytes == expectedBytes {
            try fileHandle?.close()
            fileHandle = nil
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        if receivedBytes > 0 {
            rangeHeader = "bytes=\(receivedBytes)-"
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                task.resume()
            }
        } onCancel: {
            self.task?.cancel()
            // Close the file on the delegate queue right away so no late data block is
            // written after a new transfer has started on the same file.
            self.delegateQueue.addOperation { self.finish(throwing: CancellationError()) }
        }
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirectedRequest = request
        redirectedRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let rangeHeader {
            redirectedRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        completionHandler(redirectedRequest)
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(throwing: URLError(.badServerResponse))
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            completionHandler(.cancel)
            finish(throwing: HTTPError(
                statusCode: response.statusCode,
                host: response.url?.host ?? "Hugging Face"
            ))
            return
        }
        if initialBytes > 0,
           (response.statusCode != 206 || !hasExpectedContentRange(response)) {
            completionHandler(.cancel)
            finish(throwing: ResumeRejectedError())
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        do {
            guard receivedBytes + Int64(data.count) <= expectedBytes else {
                task?.cancel()
                finish(throwing: ResumeRejectedError())
                return
            }
            try fileHandle?.write(contentsOf: data)
            receivedBytes += Int64(data.count)
            progress?(min(receivedBytes, expectedBytes))
        } catch {
            task?.cancel()
            finish(throwing: error)
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(throwing: error)
        } else if receivedBytes != expectedBytes {
            finish(throwing: URLError(.cannotDecodeContentData))
        } else {
            finish(throwing: nil)
        }
    }

    private func finish(throwing error: Error?) {
        guard !finished else { return }
        finished = true
        try? fileHandle?.close()
        fileHandle = nil
        session?.finishTasksAndInvalidate()
        let continuation = continuation
        self.continuation = nil
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    private func hasExpectedContentRange(_ response: HTTPURLResponse) -> Bool {
        guard let contentRange = response.value(forHTTPHeaderField: "Content-Range")?.lowercased() else {
            return false
        }
        return contentRange.hasPrefix("bytes \(initialBytes)-")
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ModelDownloader.fileSize(url)
    }
}
