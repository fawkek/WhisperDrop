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
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let resumedBytes = min(file.size, fileSize(partial))
            let bytesBeforeFile = completedBytes - resumedBytes
            let remoteURL = try remoteURL(for: file.path)
            var retry = 0
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

    private static func repairValidOversizedFiles() throws {
        for file in files {
            guard let expectedHash = file.sha256 else { continue }
            let destination = ModelLocator.modelFolder.appending(path: file.path)
            guard fileSize(destination) > file.size,
                  try sha256Prefix(of: destination, byteCount: file.size) == expectedHash else { continue }
            let handle = try FileHandle(forWritingTo: destination)
            try handle.truncate(atOffset: UInt64(file.size))
            try handle.close()
            let stalePartial = destination.appendingPathExtension("partial")
            if FileManager.default.fileExists(atPath: stalePartial.path) {
                try FileManager.default.removeItem(at: stalePartial)
            }
        }
    }

    private static func sha256Prefix(of url: URL, byteCount: Int64) throws -> String {
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

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { return 0 }
        return Int64(values?.fileSize ?? 0)
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
            try FileManager.default.removeItem(at: partialURL)
            receivedBytes = 0
        }
        if !FileManager.default.fileExists(atPath: partialURL.path) {
            _ = FileManager.default.createFile(atPath: partialURL.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: partialURL)
        try fileHandle?.seekToEnd()
        progress(receivedBytes)
        if receivedBytes == expectedBytes {
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
        if receivedBytes > 0, response.statusCode != 206 {
            completionHandler(.cancel)
            finish(throwing: ResumeRejectedError())
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        do {
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

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
