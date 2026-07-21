@preconcurrency import AVFoundation
import Foundation

enum AudioExtractor {
    static func prepare(_ source: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let directlySupported = ["wav", "mp3", "m4a", "flac", "aiff", "aif", "caf"]
        guard !directlySupported.contains(source.pathExtension.lowercased()) else { return source }

        let output = FileManager.default.temporaryDirectory
            .appending(path: "WhisperDrop-\(UUID().uuidString).m4a")
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let observer = Task {
            while !Task.isCancelled {
                progress(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        defer { observer.cancel() }

        exporter.outputURL = output
        exporter.outputFileType = .m4a
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .failed:
                        continuation.resume(throwing: exporter.error ?? CocoaError(.fileReadUnknown))
                    default:
                        continuation.resume(throwing: exporter.error ?? CocoaError(.fileReadUnknown))
                    }
                }
            }
        } onCancel: {
            exporter.cancelExport()
        }
        progress(1)
        return output
    }
}
